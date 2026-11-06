import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/device_identity.dart';
import '../../../data/local/prefs_service.dart';
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
        if (phase == RoundPhase.setup || phase == RoundPhase.finished) {
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
    state = state.copyWith(
      snapshot: RoomSnapshot(room: room, players: _players),
      joining: false,
    );
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
