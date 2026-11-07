import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/device_identity.dart';
import '../../../data/local/prefs_service.dart';
import '../../../data/remote/duel_repository.dart';
import '../../../data/remote/room_repository.dart' show RoomUnavailable;
import '../domain/duel_models.dart';

class DuelState {
  const DuelState({
    this.board,
    this.deviceId,
    this.busy = false,
    this.error,
  });

  final DuelBoard? board;
  final String? deviceId;
  final bool busy;
  final String? error;

  bool get inDuel => board != null;

  DuelState copyWith({
    DuelBoard? board,
    String? deviceId,
    bool? busy,
    String? error,
    bool clearError = false,
    bool clearDuel = false,
  }) {
    return DuelState(
      board: clearDuel ? null : (board ?? this.board),
      deviceId: deviceId ?? this.deviceId,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// The asynchronous mode: nobody has to be free at the same time.
///
/// Everyone plays a round whenever they like, and the longest one that day
/// wins the day. This is the only part of the app with a reason to be opened
/// on an ordinary weekday.
class DuelSession extends Notifier<DuelState> {
  StreamSubscription<List<DuelScore>>? _sub;

  DuelRepo get _repo => ref.read(duelRepositoryProvider);
  PrefsService get _prefs => ref.read(prefsServiceProvider);

  @override
  DuelState build() {
    ref.onDispose(_stop);
    return const DuelState();
  }

  Future<void> create(String name) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final duel = await _repo.createDuel(
        name: name.trim().isEmpty ? 'Focus Duel' : name.trim(),
      );
      await _prefs.setDuelCode(duel.code);
      await _attach(duel);
    } catch (e) {
      state = state.copyWith(busy: false, error: _message(e));
    }
  }

  Future<void> join(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.length != 4) {
      state = state.copyWith(error: 'A duel code is four letters.');
      return;
    }

    state = state.copyWith(busy: true, clearError: true);
    try {
      final duel = await _repo.findDuel(code);
      await _prefs.setDuelCode(code);
      await _attach(duel);
    } catch (e) {
      state = state.copyWith(busy: false, error: _message(e));
    }
  }

  /// Reconnects to the saved duel on launch. Silent on failure — a duel that
  /// has gone away should not greet the player with an error.
  Future<void> restore() async {
    final code = await _prefs.duelCode();
    if (code == null || state.inDuel) return;
    try {
      final duel = await _repo.findDuel(code);
      await _attach(duel);
    } catch (_) {
      await _prefs.setDuelCode(null);
    }
  }

  Future<void> leave() async {
    _stop();
    await _prefs.setDuelCode(null);
    state = const DuelState();
  }

  void dismissError() => state = state.copyWith(clearError: true);

  /// Sends a finished round if it beats today's best.
  ///
  /// Called for every solo round: being in a duel should not mean choosing a
  /// different mode, it should just mean your rounds count for something.
  Future<void> submitRound(Duration lasted) async {
    final board = state.board;
    if (board == null) return;

    final deviceId = await ref.read(deviceIdentityProvider).id();
    if (!beatsToday(lasted, board.scoreFor(deviceId)?.best)) return;

    try {
      await _repo.submit(
        code: board.duel.code,
        deviceId: deviceId,
        name: await _prefs.playerName(),
        best: lasted,
      );
      await refresh();
    } catch (_) {/* the round still counts locally */}
  }

  Future<void> refresh() async {
    final board = state.board;
    if (board == null) return;
    try {
      final scores = await _repo.todayScores(board.duel.code);
      final wins = await _repo.wins(board.duel.code);
      state = state.copyWith(
        board: DuelBoard(duel: board.duel, scores: scores, wins: wins),
      );
    } catch (_) {}
  }

  Future<void> _attach(Duel duel) async {
    _stop();
    final deviceId = await ref.read(deviceIdentityProvider).id();

    state = DuelState(
      board: DuelBoard(duel: duel, scores: const []),
      deviceId: deviceId,
      busy: false,
    );

    await refresh();

    _sub = _repo.watchToday(duel.code).listen(
      (scores) {
        final current = state.board;
        if (current == null) return;
        state = state.copyWith(
          board: DuelBoard(
            duel: current.duel,
            scores: scores,
            wins: current.wins,
          ),
        );
      },
      onError: (Object _) {/* a dropped stream is not worth alarming anyone */},
    );
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
  }

  String _message(Object error) =>
      error is RoomUnavailable ? error.message : 'Something went wrong.';
}

final duelSessionProvider =
    NotifierProvider<DuelSession, DuelState>(DuelSession.new);
