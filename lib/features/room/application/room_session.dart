import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/device_identity.dart';
import '../../../data/local/prefs_service.dart';
import '../../../data/remote/analytics_service.dart';
import '../../../data/remote/room_repository.dart';
import '../../detector/domain/detector_models.dart';
import '../../game/application/game_controller.dart';
import '../../game/domain/game_models.dart';
import '../domain/room_models.dart';

/// This phone's view of the table it is sitting at.
class RoomSessionState {
  const RoomSessionState({
    this.code,
    this.deviceId,
    this.snapshot,
    this.joining = false,
    this.error,
  });

  final String? code;
  final String? deviceId;
  final RoomSnapshot? snapshot;
  final bool joining;
  final String? error;

  bool get inRoom => code != null;
  bool get isHost =>
      snapshot != null && deviceId != null && snapshot!.room.isHost(deviceId!);

  RoomSessionState copyWith({
    String? code,
    String? deviceId,
    RoomSnapshot? snapshot,
    bool? joining,
    String? error,
    bool clearError = false,
    bool clearRoom = false,
  }) {
    return RoomSessionState(
      code: clearRoom ? null : (code ?? this.code),
      deviceId: deviceId ?? this.deviceId,
      snapshot: clearRoom ? null : (snapshot ?? this.snapshot),
      joining: joining ?? this.joining,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Keeps the room and the local game in step.
///
/// The server is not an authority on the game — each phone decides for itself
/// whether it was picked up, and merely reports it. The only thing resolved
/// centrally is *who was first*, by comparing timestamps.
class RoomSession extends Notifier<RoomSessionState> {
  StreamSubscription<Room?>? _roomSub;
  StreamSubscription<List<RoomPlayer>>? _playersSub;
  ProviderSubscription<GameState>? _gameSub;

  Room? _room;
  List<RoomPlayer> _players = const [];
  bool _reportedThisRound = false;

  RoomRepository get _repo => ref.read(roomRepositoryProvider);

  @override
  RoomSessionState build() {
    ref.onDispose(_stopWatching);
    return const RoomSessionState();
  }

  Future<String> _name() => ref.read(prefsServiceProvider).playerName();
  Future<String> _deviceId() => ref.read(deviceIdentityProvider).id();

  // ---- joining ---------------------------------------------------------------

  Future<void> host(GameConfig config) async {
    state = state.copyWith(joining: true, clearError: true);
    try {
      final deviceId = await _deviceId();
      final room = await _repo.createRoom(
        deviceId: deviceId,
        name: await _name(),
        config: config,
      );
      _attach(room.code, deviceId);
      ref.read(analyticsProvider).roomCreated();
    } catch (e) {
      state = state.copyWith(joining: false, error: _message(e));
    }
  }

  Future<void> join(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.length != 4) {
      state = state.copyWith(error: 'A table code is four letters.');
      return;
    }

    state = state.copyWith(joining: true, clearError: true);
    try {
      final deviceId = await _deviceId();
      await _repo.joinRoom(code: code, deviceId: deviceId, name: await _name());
      _attach(code, deviceId);
      ref.read(analyticsProvider).roomJoined();
    } catch (e) {
      state = state.copyWith(joining: false, error: _message(e));
    }
  }

  Future<void> leave() async {
    final code = state.code;
    final deviceId = state.deviceId;
    _stopWatching();
    state = const RoomSessionState();
    if (code != null && deviceId != null) {
      try {
        await _repo.leaveRoom(code: code, deviceId: deviceId);
      } catch (_) {/* leaving is best-effort */}
    }
  }

  // ---- host actions ----------------------------------------------------------

  /// Host: send the whole table into the round.
  Future<void> startRound() async {
    final code = state.code;
    if (code == null || !state.isHost) return;
    try {
      await _repo.resetRound(code);
      await _repo.setStatus(code, RoomStatus.settling);
    } catch (e) {
      state = state.copyWith(error: _message(e));
    }
  }

  /// Host: back to the lobby for another round.
  Future<void> backToLobby() async {
    final code = state.code;
    if (code == null || !state.isHost) return;
    try {
      await _repo.resetRound(code);
      await _repo.setStatus(code, RoomStatus.lobby);
    } catch (e) {
      state = state.copyWith(error: _message(e));
    }
  }

  // ---- wiring ----------------------------------------------------------------

  void _attach(String code, String deviceId) {
    _stopWatching();
    _reportedThisRound = false;
    state = RoomSessionState(code: code, deviceId: deviceId, joining: false);

    _roomSub = _repo.watchRoom(code).listen(
      (room) {
        if (room == null) {
          // The host closed the table.
          _stopWatching();
          state = const RoomSessionState(error: 'The table was closed.');
          return;
        }
        _room = room;
        _publish();
        _followRoomStatus(room);
      },
      onError: (Object e) => state = state.copyWith(error: _message(e)),
    );

    _playersSub = _repo.watchPlayers(code).listen(
      (players) {
        _players = players;
        _publish();
      },
      onError: (Object e) => state = state.copyWith(error: _message(e)),
    );

    // Report this phone's own catch, once per round.
    _gameSub = ref.listen<GameState>(gameControllerProvider, (previous, next) {
      if (next.phase != RoundPhase.finished) return;
      final result = next.result;
      if (result == null || result.outcome != RoundOutcome.caught) return;
      _reportCaught(result);
    });
  }

  /// The host's room status drives every phone, so nobody has to tap "go" at
  /// the same moment.
  void _followRoomStatus(Room room) {
    final game = ref.read(gameControllerProvider.notifier);
    final phase = ref.read(gameControllerProvider).phase;

    switch (room.status) {
      case RoomStatus.settling:
        // Only from `setup`. Starting from `finished` too would restart the
        // round the instant it ended — the result screen would never be seen,
        // because the room sits in `settling` for the whole round.
        if (phase == RoundPhase.setup) {
          _reportedThisRound = false;
          game
            ..setStake(room.config.stake, custom: room.config.customStake)
            ..setTarget(room.config.target)
            ..start();
        }
      case RoomStatus.lobby:
        if (phase != RoundPhase.setup) game.reset();
      case RoomStatus.running:
      case RoomStatus.finished:
        break;
    }
  }

  /// Host only: once at most one player is left standing the round is over,
  /// so close it for everyone. Without this the room stays in `settling`
  /// forever and nothing can tell that a round ended.
  Future<void> _closeRoundIfDecided(RoomSnapshot snapshot) async {
    if (!state.isHost) return;
    if (snapshot.room.status != RoomStatus.settling) return;
    if (!snapshot.isDecided) return;

    try {
      await _repo.setStatus(snapshot.room.code, RoomStatus.finished);
    } catch (_) {/* the local result still stands */}
  }

  /// Host only: send the table back to the lobby and straight into a new
  /// round. Two steps because every phone resets on `lobby` before it can be
  /// started again.
  Future<void> playAgain() async {
    final code = state.code;
    if (code == null || !state.isHost) return;
    try {
      await _repo.resetRound(code);
      await _repo.setStatus(code, RoomStatus.lobby);
      // Let every phone process the reset before arming them again.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _repo.setStatus(code, RoomStatus.settling);
    } catch (e) {
      state = state.copyWith(error: _message(e));
    }
  }

  Future<void> _reportCaught(RoundResult result) async {
    final code = state.code;
    final deviceId = state.deviceId;
    if (code == null || deviceId == null || _reportedThisRound) return;
    _reportedThisRound = true;

    try {
      await _repo.reportCaught(
        code: code,
        deviceId: deviceId,
        lasted: result.lasted,
        reason: result.reason ?? CatchReason.motion,
      );
    } catch (_) {
      // The local result still stands; the table just won't see it.
      _reportedThisRound = false;
    }
  }

  void _publish() {
    final room = _room;
    if (room == null) return;
    final snapshot = RoomSnapshot(room: room, players: _players);
    state = state.copyWith(snapshot: snapshot, joining: false);
    _closeRoundIfDecided(snapshot);
  }

  void _stopWatching() {
    _roomSub?.cancel();
    _roomSub = null;
    _playersSub?.cancel();
    _playersSub = null;
    _gameSub?.close();
    _gameSub = null;
    _room = null;
    _players = const [];
  }

  String _message(Object error) =>
      error is RoomUnavailable ? error.message : 'Something went wrong.';
}

final roomSessionProvider =
    NotifierProvider<RoomSession, RoomSessionState>(RoomSession.new);
