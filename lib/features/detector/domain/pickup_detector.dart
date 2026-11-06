import 'dart:math' as math;

import '../../../core/constants/detection_config.dart';
import 'detector_models.dart';

/// The heart of the app: decides whether a phone has been picked up.
///
/// Deliberately pure — no sensors, no Flutter, no clock of its own. Samples and
/// timestamps are fed in, so the whole thing is unit-testable and the thresholds
/// can be regression-tested against recorded traces.
///
/// How it works:
///  1. A low-pass filter tracks gravity, so the device's resting orientation is
///     learned rather than assumed. (A phone face down on a table still reads
///     ~9.8 m/s² on one axis.)
///  2. Subtracting gravity leaves linear acceleration — actual movement.
///  3. The phone must hold still for [DetectionConfig.stillnessWindow] before
///     the round arms, which guarantees it is really on the table.
///  4. Once armed, movement must be *sustained* for
///     [DetectionConfig.sustainedMotionWindow] to count. This single rule is
///     what keeps a passing truck or a bumped table from ending the game.
class PickupDetector {
  DetectorState _state = DetectorState.idle;

  // Running gravity estimate, one component per axis.
  double _gx = 0, _gy = 0, _gz = 0;
  bool _gravityInitialised = false;

  double _linear = 0;
  double _rotation = 0;

  Duration? _stillSince;
  Duration? _motionSince;
  Duration? _armedAt;
  Duration _roundStart = Duration.zero;

  CatchReason? _reason;
  Duration? _caughtAt;

  DetectorState get state => _state;

  /// Begin watching. The phone is expected to be placed down now; the detector
  /// waits for stillness before it arms.
  DetectorSnapshot start(Duration now) {
    _state = DetectorState.settling;
    _roundStart = now;
    _lastNow = now;
    _stillSince = null;
    _motionSince = null;
    _armedAt = null;
    _reason = null;
    _caughtAt = null;
    // Re-learn gravity from scratch: the phone is being placed down now, very
    // possibly in a different orientation than the last round.
    _gravityInitialised = false;
    return snapshot;
  }

  /// Stop watching and clear the catch.
  DetectorSnapshot reset() {
    _state = DetectorState.idle;
    _stillSince = null;
    _motionSince = null;
    _armedAt = null;
    _reason = null;
    _caughtAt = null;
    _linear = 0;
    _rotation = 0;
    return snapshot;
  }

  /// Catch this phone for a reason the sensors cannot see — leaving the app,
  /// unlocking the screen, or conceding.
  DetectorSnapshot trigger(CatchReason reason, Duration now) {
    if (!_isWatching) return snapshot;
    return _catch(reason, now);
  }

  /// Feed an accelerometer sample (m/s², gravity included).
  DetectorSnapshot onAccelerometer(double x, double y, double z, Duration now) {
    if (!_gravityInitialised) {
      _gx = x;
      _gy = y;
      _gz = z;
      _gravityInitialised = true;
      _linear = 0;
      return _evaluate(now);
    }

    // How far this sample is from the current gravity estimate — i.e. movement.
    final candidate = _magnitude(x - _gx, y - _gy, z - _gz);

    // While armed, freeze the estimate during movement so bumps cannot bias it.
    // While settling or idle, track quickly: the resting orientation is still
    // being learned, and the stillness check verifies convergence.
    final shouldUpdate = _state != DetectorState.armed ||
        candidate < DetectionConfig.gravityUpdateGate;

    if (shouldUpdate) {
      final a = _state == DetectorState.armed
          ? DetectionConfig.gravitySmoothing
          : DetectionConfig.gravitySmoothingSettling;
      _gx = a * _gx + (1 - a) * x;
      _gy = a * _gy + (1 - a) * y;
      _gz = a * _gz + (1 - a) * z;
      _linear = _magnitude(x - _gx, y - _gy, z - _gz);
    } else {
      _linear = candidate;
    }

    return _evaluate(now);
  }

  /// Feed a gyroscope sample (rad/s). Optional — phones without a gyroscope
  /// still work, they just rely on acceleration alone.
  DetectorSnapshot onGyroscope(double x, double y, double z, Duration now) {
    _rotation = _magnitude(x, y, z);
    return _evaluate(now);
  }

  DetectorSnapshot _evaluate(Duration now) {
    _lastNow = now;

    switch (_state) {
      case DetectorState.settling:
        final isStill = _linear < DetectionConfig.stillnessTolerance &&
            _rotation < DetectionConfig.stillnessTolerance;
        if (!isStill) {
          _stillSince = null;
        } else {
          _stillSince ??= now;
          if (now - _stillSince! >= DetectionConfig.stillnessWindow) {
            _state = DetectorState.armed;
            _armedAt = now;
            _motionSince = null;
          }
        }

      case DetectorState.armed:
        // Grace window: putting the phone down should not catch the person
        // who just put it down.
        if (now - _armedAt! < DetectionConfig.armingGrace) {
          _motionSince = null;
          break;
        }

        final movedLinearly =
            _linear > DetectionConfig.pickUpAccelThreshold;
        final rotated = _rotation > DetectionConfig.pickUpGyroThreshold;

        if (!movedLinearly && !rotated) {
          _motionSince = null;
        } else {
          _motionSince ??= now;
          if (now - _motionSince! >= DetectionConfig.sustainedMotionWindow) {
            return _catch(
              movedLinearly ? CatchReason.motion : CatchReason.rotation,
              now,
            );
          }
        }

      case DetectorState.idle:
      case DetectorState.caught:
        break;
    }

    return snapshot;
  }

  DetectorSnapshot _catch(CatchReason reason, Duration now) {
    _state = DetectorState.caught;
    _reason = reason;
    _caughtAt = now - _roundStart;
    _motionSince = null;
    return snapshot;
  }

  bool get _isWatching =>
      _state == DetectorState.settling || _state == DetectorState.armed;

  DetectorSnapshot get snapshot => DetectorSnapshot(
        state: _state,
        linearAcceleration: _linear,
        rotationRate: _rotation,
        stillHoldProgress: _progress(_stillSince, DetectionConfig.stillnessWindow),
        motionHoldProgress:
            _progress(_motionSince, DetectionConfig.sustainedMotionWindow),
        reason: _reason,
        caughtAt: _caughtAt,
      );

  /// Progress through a hold window, clamped to 0–1, measured against the most
  /// recent sample's timestamp.
  double _progress(Duration? since, Duration window) {
    if (since == null) return 0;
    final held = _lastNow - since;
    if (held <= Duration.zero) return 0;
    final ratio = held.inMicroseconds / window.inMicroseconds;
    return ratio.clamp(0.0, 1.0);
  }

  /// Timestamp of the most recent sample. Samples carry the clock.
  Duration _lastNow = Duration.zero;

  static double _magnitude(double x, double y, double z) =>
      math.sqrt(x * x + y * y + z * z);
}
