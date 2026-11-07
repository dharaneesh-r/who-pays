import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:who_pays/core/feedback/alarm_service.dart';
import 'package:who_pays/features/detector/application/detector_service.dart';
import 'package:who_pays/features/detector/domain/detector_models.dart';
import 'package:who_pays/features/game/application/game_controller.dart';
import 'package:who_pays/features/game/domain/game_models.dart';

/// A detector a test can drive by hand — no sensors, no plugins, no waiting.
class FakeDetector implements Detector {
  final _controller = StreamController<DetectorSnapshot>.broadcast();

  DetectorSnapshot _snapshot = const DetectorSnapshot.idle();
  int startCount = 0;
  int stopCount = 0;
  CatchReason? lastTrigger;

  @override
  Stream<DetectorSnapshot> get snapshots => _controller.stream;

  @override
  DetectorSnapshot get snapshot => _snapshot;

  @override
  void start() {
    startCount++;
    emit(DetectorState.settling);
  }

  @override
  void stop() {
    stopCount++;
    emit(DetectorState.idle);
  }

  @override
  void trigger(CatchReason reason) {
    lastTrigger = reason;
    emit(DetectorState.caught, reason: reason);
  }

  @override
  void dispose() => _controller.close();

  /// Push a state through as the real detector would.
  void emit(DetectorState state, {CatchReason? reason}) {
    _snapshot = DetectorSnapshot(
      state: state,
      linearAcceleration: 0,
      rotationRate: 0,
      stillHoldProgress: 0,
      motionHoldProgress: 0,
      reason: reason,
    );
    _controller.add(_snapshot);
  }
}

/// Silent alarm. Records what the game asked for so the test can assert it.
class FakeAlarm implements Alarm {
  int fired = 0;
  int silenced = 0;
  int ticked = 0;
  bool? awake;

  @override
  Future<void> fire() async => fired++;
  @override
  Future<void> silence() async => silenced++;
  @override
  Future<void> tick() async => ticked++;
  @override
  Future<void> warmUp() async {}
  @override
  Future<void> keepAwake(bool enabled) async => awake = enabled;
  @override
  Future<void> dispose() async {}
}

void main() {
  late FakeDetector detector;
  late FakeAlarm alarm;
  late ProviderContainer container;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    detector = FakeDetector();
    alarm = FakeAlarm();
    container = ProviderContainer(overrides: [
      detectorServiceProvider.overrideWithValue(detector),
      alarmServiceProvider.overrideWithValue(alarm),
    ]);
    // Keep the notifier alive for the whole test.
    container.listen(gameControllerProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  // Local functions, not getters: a function body cannot declare getters.
  GameState state() => container.read(gameControllerProvider);
  GameController controller() =>
      container.read(gameControllerProvider.notifier);

  /// The detector emits asynchronously, like the real one.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  group('round lifecycle', () {
    test('starts in setup', () {
      expect(state().phase, RoundPhase.setup);
      expect(state().result, isNull);
    });

    test('start() puts the round into settling and arms the detector', () async {
      controller().start();
      await settle();

      expect(detector.startCount, 1);
      expect(state().phase, RoundPhase.settling);
      expect(alarm.awake, isTrue, reason: 'the clock must stay visible');
    });

    test('the clock only begins once the detector arms', () async {
      controller().start();
      await settle();
      expect(state().phase, RoundPhase.settling);

      detector.emit(DetectorState.armed);
      await settle();

      expect(state().phase, RoundPhase.running);
      expect(state().elapsed, Duration.zero,
          reason: 'nobody is scored for the seconds spent putting phones down');
    });
  });

  group('being caught', () {
    Future<void> playUntilCaught({CatchReason reason = CatchReason.motion}) async {
      controller().start();
      await settle();
      detector.emit(DetectorState.armed);
      await settle();
      detector.emit(DetectorState.caught, reason: reason);
      await settle();
    }

    test('a catch ends the round and records why', () async {
      await playUntilCaught(reason: CatchReason.leftApp);

      expect(state().phase, RoundPhase.finished);
      expect(state().result?.outcome, RoundOutcome.caught);
      expect(state().result?.reason, CatchReason.leftApp);
    });

    test('the siren fires and the screen is released', () async {
      await playUntilCaught();

      expect(alarm.fired, 1);
      expect(alarm.awake, isFalse);
    });

    test('a finished round is final — later sensor noise cannot change it',
        () async {
      await playUntilCaught(reason: CatchReason.motion);
      final decided = state().result;

      // The real detector keeps emitting as the phone is handled afterwards.
      detector.emit(DetectorState.settling);
      detector.emit(DetectorState.armed);
      await settle();

      expect(state().phase, RoundPhase.finished);
      expect(state().result?.reason, decided?.reason);
    });

    test('concede reaches the detector as a conceded catch', () async {
      controller().start();
      await settle();
      detector.emit(DetectorState.armed);
      await settle();

      controller().concede();
      await settle();

      expect(detector.lastTrigger, CatchReason.conceded);
      expect(state().result?.reason, CatchReason.conceded);
    });

    test('concede does nothing once the round is over', () async {
      await playUntilCaught();
      detector.lastTrigger = null;

      controller().concede();
      await settle();

      expect(detector.lastTrigger, isNull);
    });
  });

  group('reset', () {
    test('returns to setup, stops the detector and silences the alarm',
        () async {
      controller().start();
      await settle();
      detector.emit(DetectorState.armed);
      await settle();

      controller().reset();
      await settle();

      expect(state().phase, RoundPhase.setup);
      expect(state().result, isNull);
      expect(detector.stopCount, 1);
      expect(alarm.silenced, greaterThan(0));
      expect(alarm.awake, isFalse);
    });

    test('a new round can be started after a catch', () async {
      controller().start();
      await settle();
      detector.emit(DetectorState.armed);
      await settle();
      detector.emit(DetectorState.caught, reason: CatchReason.motion);
      await settle();

      controller().start();
      await settle();

      expect(detector.startCount, 2);
      expect(state().phase, RoundPhase.settling);
      expect(state().result, isNull, reason: 'the old verdict must be cleared');
    });
  });

  group('configuration', () {
    test('stake and length are kept for the round', () {
      controller().setStake(Stake.dishes);
      controller().setTarget(const Duration(minutes: 15));

      expect(state().config.stake, Stake.dishes);
      expect(state().config.target, const Duration(minutes: 15));
      expect(state().config.stakeText, 'does the dishes');
      expect(state().config.stakeTextYou, 'do the dishes');
    });

    test('an open-ended round has no target progress', () {
      controller().setTarget(null);
      expect(state().config.target, isNull);
      expect(state().targetProgress, isNull);
    });
  });
}
