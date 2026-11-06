import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/core/constants/detection_config.dart';
import 'package:who_pays/features/detector/domain/detector_models.dart';
import 'package:who_pays/features/detector/domain/pickup_detector.dart';

/// These tests are the safety net for the single most important behaviour in
/// the app. A false positive ends a game and the group deletes the app, so the
/// "bumped table" case matters as much as the "picked it up" case.
void main() {
  const step = DetectionConfig.samplingInterval; // 20 ms
  const gravity = 9.81;

  /// Feeds [duration] of samples at the real sampling rate, starting at [from].
  /// [extra] is added to the z axis on top of gravity, simulating movement.
  Duration feed(
    PickupDetector d,
    Duration from,
    Duration duration, {
    double extra = 0,
    double spin = 0,
  }) {
    var now = from;
    final end = from + duration;
    while (now < end) {
      d.onAccelerometer(0, 0, gravity + extra, now);
      d.onGyroscope(0, 0, spin, now);
      now += step;
    }
    return now;
  }

  /// Puts the detector into the armed state past its arming grace period.
  (PickupDetector, Duration) armed() {
    final d = PickupDetector();
    d.start(Duration.zero);
    var now = feed(d, Duration.zero, DetectionConfig.stillnessWindow + step * 2);
    expect(d.state, DetectorState.armed, reason: 'should arm once still');
    now = feed(d, now, DetectionConfig.armingGrace + step * 2);
    return (d, now);
  }

  group('arming', () {
    test('starts in idle and only watches after start()', () {
      final d = PickupDetector();
      expect(d.state, DetectorState.idle);
      d.start(Duration.zero);
      expect(d.state, DetectorState.settling);
    });

    test('arms after the phone is still for the stillness window', () {
      final d = PickupDetector();
      d.start(Duration.zero);

      feed(d, Duration.zero, DetectionConfig.stillnessWindow - step * 3);
      expect(d.state, DetectorState.settling,
          reason: 'not still long enough yet');

      feed(d, DetectionConfig.stillnessWindow - step * 3, step * 6);
      expect(d.state, DetectorState.armed);
    });

    test('does not arm while the phone is being fidgeted with', () {
      final d = PickupDetector();
      d.start(Duration.zero);

      // Real fidgeting alternates direction. (A *constant* offset is not
      // movement at all — it is a new resting orientation, and the gravity
      // filter is supposed to absorb it.)
      var now = Duration.zero;
      final end = DetectionConfig.stillnessWindow * 3;
      var sign = 1;
      while (now < end) {
        d.onAccelerometer(0, 0, gravity + 4 * sign, now);
        d.onGyroscope(0, 0, 2.0 * sign, now);
        sign = -sign;
        now += step;
      }

      expect(d.state, DetectorState.settling,
          reason: 'continuous movement must never arm the round');
    });

    test('ignores movement during the arming grace period', () {
      final d = PickupDetector();
      d.start(Duration.zero);
      var now = feed(d, Duration.zero, DetectionConfig.stillnessWindow + step * 2);
      expect(d.state, DetectorState.armed);

      // The person who set the phone down is still moving their hand away.
      now = feed(d, now, DetectionConfig.armingGrace - step * 5, extra: 6);
      expect(d.state, DetectorState.armed,
          reason: 'must not catch the player who just put the phone down');
    });
  });

  group('catching', () {
    test('catches a sustained pick-up', () {
      final (d, now) = armed();
      feed(d, now, DetectionConfig.sustainedMotionWindow + step * 3, extra: 6);

      expect(d.state, DetectorState.caught);
      expect(d.snapshot.reason, CatchReason.motion);
      expect(d.snapshot.caughtAt, isNotNull);
    });

    test('catches a sustained rotation even without linear movement', () {
      final (d, now) = armed();
      feed(d, now, DetectionConfig.sustainedMotionWindow + step * 3, spin: 3);

      expect(d.state, DetectorState.caught);
      expect(d.snapshot.reason, CatchReason.rotation);
    });

    test('does NOT catch a brief table bump', () {
      final (d, now) = armed();

      // A thump on the table: well over threshold, but far too short.
      final after = feed(d, now, step * 4, extra: 8);
      expect(d.state, DetectorState.armed,
          reason: 'a bump shorter than the sustained window must be ignored');

      // And the hold resets, so repeated bumps never accumulate into a catch.
      feed(d, after, DetectionConfig.sustainedMotionWindow * 2);
      expect(d.snapshot.motionHoldProgress, 0);
      expect(d.state, DetectorState.armed);
    });

    test('repeated bumps separated by stillness never add up to a catch', () {
      var (d, now) = armed();
      for (var i = 0; i < 8; i++) {
        now = feed(d, now, step * 4, extra: 8); // bump
        now = feed(d, now, step * 10); // settle
      }
      expect(d.state, DetectorState.armed);
    });

    test('leaving the app catches immediately', () {
      final (d, now) = armed();
      d.trigger(CatchReason.leftApp, now);

      expect(d.state, DetectorState.caught);
      expect(d.snapshot.reason, CatchReason.leftApp);
    });

    test('an external trigger does nothing when not watching', () {
      final d = PickupDetector();
      d.trigger(CatchReason.leftApp, Duration.zero);
      expect(d.state, DetectorState.idle);
    });

    test('stays caught — no further sample can un-catch it', () {
      final (d, now) = armed();
      final after =
          feed(d, now, DetectionConfig.sustainedMotionWindow + step * 3, extra: 6);
      expect(d.state, DetectorState.caught);

      feed(d, after, DetectionConfig.stillnessWindow * 2);
      expect(d.state, DetectorState.caught,
          reason: 'putting the phone back down does not undo losing');
    });

    test('records how long the player lasted', () {
      final (d, now) = armed();
      feed(d, now, DetectionConfig.sustainedMotionWindow + step * 3, extra: 6);

      final lasted = d.snapshot.caughtAt!;
      expect(lasted, greaterThanOrEqualTo(DetectionConfig.armingGrace));
    });
  });

  group('gravity handling', () {
    test('works in any resting orientation, not just face down', () {
      // Phone propped on its side: gravity is on the x axis.
      final d = PickupDetector();
      d.start(Duration.zero);

      var now = Duration.zero;
      final end = DetectionConfig.stillnessWindow + step * 2;
      while (now < end) {
        d.onAccelerometer(gravity, 0, 0, now);
        d.onGyroscope(0, 0, 0, now);
        now += step;
      }

      expect(d.state, DetectorState.armed,
          reason: 'gravity is learned per axis, not assumed to be on z');
    });

    test('the gravity filter does not absorb a real pick-up', () {
      final (d, now) = armed();

      // Constant offset — the worst case for a low-pass gravity filter.
      feed(d, now, DetectionConfig.sustainedMotionWindow + step * 2, extra: 3);
      expect(d.state, DetectorState.caught,
          reason: 'filter must be slower than the sustained-motion window');
    });
  });

  group('reset', () {
    test('reset returns to idle and clears the catch', () {
      final (d, now) = armed();
      feed(d, now, DetectionConfig.sustainedMotionWindow + step * 3, extra: 6);
      expect(d.state, DetectorState.caught);

      d.reset();
      expect(d.state, DetectorState.idle);
      expect(d.snapshot.reason, isNull);
      expect(d.snapshot.caughtAt, isNull);
    });
  });
}
