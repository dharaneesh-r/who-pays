import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/alarm_service.dart';
import '../../detector/application/detector_service.dart';
import '../../detector/domain/detector_models.dart';
import '../domain/game_models.dart';

/// Drives one round: setup → settling → running → finished.
///
/// The detector decides *whether* someone is caught; this decides what that
/// means for the round. The elapsed clock starts when the round arms, not when
/// the player taps start, so nobody is scored for the seconds spent putting
/// phones down.
class GameController extends Notifier<GameState> {
  Timer? _ticker;
  StreamSubscription<DetectorSnapshot>? _sub;
  final _clock = Stopwatch();

  static const _tick = Duration(milliseconds: 200);

  @override
  GameState build() {
    ref.onDispose(_teardown);
    return const GameState();
  }

  DetectorService get _detector => ref.read(detectorServiceProvider);
  AlarmService get _alarm => ref.read(alarmServiceProvider);

  // ---- setup ----------------------------------------------------------------

  void setStake(Stake stake, {String? custom}) {
    state = state.copyWith(
      config: state.config.copyWith(stake: stake, customStake: custom),
    );
  }

  void setTarget(Duration? target) {
    state = state.copyWith(
      config: target == null
          ? state.config.copyWith(clearTarget: true)
          : state.config.copyWith(target: target),
    );
  }

  // ---- round ----------------------------------------------------------------

  /// Phones go down now. The round arms itself once this phone is still.
  void start() {
    _teardown();
    _clock
      ..reset()
      ..stop();

    state = state.copyWith(
      phase: RoundPhase.settling,
      elapsed: Duration.zero,
      clearResult: true,
    );

    // Silence any previous round, keep the clock visible, and pre-load the
    // siren so the first catch fires instantly.
    _alarm
      ..silence()
      ..keepAwake(true)
      ..warmUp();

    _sub = _detector.snapshots.listen(_onDetector);
    _detector.start();
  }

  /// The player gives up rather than sitting it out.
  void concede() {
    if (state.phase != RoundPhase.running &&
        state.phase != RoundPhase.settling) {
      return;
    }
    _detector.trigger(CatchReason.conceded);
  }

  /// Back to setup, ready for another round.
  void reset() {
    _teardown();
    _detector.stop();
    _alarm
      ..silence()
      ..keepAwake(false);
    state = state.copyWith(
      phase: RoundPhase.setup,
      elapsed: Duration.zero,
      detector: const DetectorSnapshot.idle(),
      clearResult: true,
    );
  }

  // ---- internals ------------------------------------------------------------

  void _onDetector(DetectorSnapshot snapshot) {
    // A finished round is final. The detector keeps emitting as the phone is
    // picked up and put down afterwards; none of that can change the result.
    if (state.phase == RoundPhase.finished) return;

    state = state.copyWith(detector: snapshot);

    switch (snapshot.state) {
      case DetectorState.armed:
        if (state.phase == RoundPhase.settling) _beginRunning();

      case DetectorState.caught:
        _finish(
          RoundResult(
            outcome: RoundOutcome.caught,
            lasted: _clock.elapsed,
            reason: snapshot.reason,
          ),
        );

      case DetectorState.idle:
      case DetectorState.settling:
        break;
    }
  }

  void _beginRunning() {
    _clock
      ..reset()
      ..start();
    state = state.copyWith(phase: RoundPhase.running, elapsed: Duration.zero);

    _ticker?.cancel();
    _ticker = Timer.periodic(_tick, (_) {
      final elapsed = _clock.elapsed;
      state = state.copyWith(elapsed: elapsed);

      final target = state.config.target;
      if (target != null && elapsed >= target) {
        _finish(
          RoundResult(outcome: RoundOutcome.survived, lasted: elapsed),
        );
      }
    });
  }

  void _finish(RoundResult result) {
    _ticker?.cancel();
    _ticker = null;
    _clock.stop();

    if (result.outcome == RoundOutcome.caught) {
      _alarm.fire();
    } else {
      // Surviving the round earns a tap, not a siren.
      _alarm.tick();
    }
    _alarm.keepAwake(false);

    state = state.copyWith(
      phase: RoundPhase.finished,
      elapsed: result.lasted,
      result: result,
    );
  }

  void _teardown() {
    _ticker?.cancel();
    _ticker = null;
    _sub?.cancel();
    _sub = null;
  }
}

final gameControllerProvider =
    NotifierProvider<GameController, GameState>(GameController.new);
