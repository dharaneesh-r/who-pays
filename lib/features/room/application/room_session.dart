import 'dart:async';

import 'package:flutter/foundation.dart';
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
  Timer? _beat;
  Timer? _presenceTick;

  Room? _room;
  List<RoomPlayer> _players = const [];

  /// Device ids currently on the realtime channel, and when each one that is
  /// missing was last seen there.
  Set<String> _online = const {};
  final Map<String, DateTime> _offlineSince = {};
  StreamSubscription<Set<String>>? _presenceSub;

  /// How long a phone must stay off the channel before the table gives up on
  /// it. Realtime reconnects after a tunnel or a wifi handover, and ejecting
  /// somebody who is sitting right there is far worse than a slow round.
  /// Not const so tests can collapse it; nothing else should change it.
  @visibleForTesting
  static Duration offlineGrace = const Duration(seconds: 30);
  bool _reportedThisRound = false;

  RoomRepo get _repo => ref.read(roomRepositoryProvider);

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
    // Leaving on purpose should not then offer to rejoin.
    unawaited(ref.read(prefsServiceProvider).setLastRoomCode(null));
    if (code != null && deviceId != null) {
      try {
        await _repo.leaveRoom(code: code, deviceId: deviceId);
      } catch (_) {/* leaving is best-effort */}
    }
  }

  /// Rejoin the table this phone was last at, after the app was killed.
  Future<void> rejoinLast() async {
    final code = await ref.read(prefsServiceProvider).lastRoomCode();
    if (code == null) return;
    await join(code);
  }

  void dismissError() => state = state.copyWith(clearError: true);

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

  /// How often this phone reports in. Must be comfortably shorter than
  /// [RoomSnapshot.presenceTimeout] so one missed beat is harmless.
  static const _heartbeat = Duration(seconds: 15);

  void _attach(String code, String deviceId) {
    _stopWatching();
    _reportedThisRound = false;
    state = RoomSessionState(code: code, deviceId: deviceId, joining: false);

    // Remember the table so a killed app can offer to rejoin it.
    unawaited(ref.read(prefsServiceProvider).setLastRoomCode(code));

    _beat?.cancel();
    _beat = Timer.periodic(_heartbeat, (_) async {
      try {
        await _repo.touch(code: code, deviceId: deviceId);
      } catch (_) {/* a missed beat is tolerated by the timeout */}
    });

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

    _presenceSub = _repo
        .watchPresence(code: code, deviceId: deviceId)
        .listen((online) {
      _online = online;
      final now = DateTime.now();
      for (final id in online) {
        _offlineSince.remove(id);
      }
      // Only start the clock on people we have actually seen connected, and
      // only while presence is working at all.
      if (_presenceWorks(deviceId)) {
        for (final p in _players) {
          if (!online.contains(p.deviceId)) {
            _offlineSince.putIfAbsent(p.deviceId, () => now);
          }
        }
      }
      _publish();
    }, onError: (Object _) {/* presence is a bonus, never a requirement */});

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
            ..start(fromRoom: true);
        }
      case RoomStatus.lobby:
        if (phase != RoundPhase.setup) game.reset();
      case RoomStatus.finished:
        // The round is over for the whole table. A phone that was caught has
        // already finished on its own; one still counting has to be told, or
        // it sits there running forever with the result already decided.
        if (phase == RoundPhase.running || phase == RoundPhase.settling) {
          game.endBecauseSomeoneElseCracked();
        }
      case RoomStatus.running:
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

  /// Presence is only believable if this phone can see itself on the channel.
  /// Otherwise the socket is down and the empty set means nothing.
  bool _presenceWorks(String? deviceId) =>
      deviceId != null && _online.contains(deviceId);

  /// Who has been off the channel long enough to count as gone.
  Set<String> get _confirmedGone {
    if (!_presenceWorks(state.deviceId)) return const {};
    final now = DateTime.now();
    return _offlineSince.entries
        .where((e) => now.difference(e.value) >= offlineGrace)
        .map((e) => e.key)
        .toSet();
  }

  void _publish() {
    final room = _room;
    if (room == null) return;
    final snapshot = RoomSnapshot(
      room: room,
      players: _players,
      confirmedGone: _confirmedGone,
    );
    state = state.copyWith(snapshot: snapshot, joining: false);
    _closeRoundIfDecided(snapshot);

    // Somebody going absent produces no database change, so nothing would
    // re-evaluate the round. Re-check on a timer while anyone is still in.
    _presenceTick ??= Timer.periodic(const Duration(seconds: 10), (_) {
      final current = state.snapshot;
      if (current == null) return;
      state = state.copyWith(
        snapshot: RoomSnapshot(
          room: current.room,
          players: current.players,
          confirmedGone: _confirmedGone,
        ),
      );
      _closeRoundIfDecided(state.snapshot!);
    });
  }

  void _stopWatching() {
    _presenceSub?.cancel();
    _presenceSub = null;
    _online = const {};
    _offlineSince.clear();
    _beat?.cancel();
    _beat = null;
    _presenceTick?.cancel();
    _presenceTick = null;
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

/// The table worth offering to rejoin: one this phone was at, that still
/// exists on the server. Null when there is nothing to go back to.
final rejoinableRoomProvider = FutureProvider<String?>((ref) async {
  final code = await ref.watch(prefsServiceProvider).lastRoomCode();
  if (code == null) return null;
  final exists = await ref.watch(roomRepositoryProvider).roomExists(code);
  if (!exists) {
    // The table is gone; stop offering it.
    await ref.read(prefsServiceProvider).setLastRoomCode(null);
    return null;
  }
  return code;
});
