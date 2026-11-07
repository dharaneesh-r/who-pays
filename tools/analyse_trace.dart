// Replays a recorded sensor trace through the real detector and reports what
// it would have done, step by step.
//
// Thresholds tuned against a simulation are guesses. A trace from the actual
// phone on the actual table is evidence, and this turns it into a verdict:
// which labelled actions were caught, which were not, and how much headroom
// each threshold had.
//
//   dart run tools/analyse_trace.dart traces/trace_123.csv

import 'dart:io';
import 'dart:math' as math;

import 'package:who_pays/core/constants/detection_config.dart';
import 'package:who_pays/features/detector/domain/detector_models.dart';
import 'package:who_pays/features/detector/domain/pickup_detector.dart';

/// Steps where a catch is correct, and steps where it is a false positive.
const shouldCatch = {'lift_slow', 'lift_normal', 'flip'};
const mustNotCatch = {'still', 'thump', 'knock', 'still_end'};
// Everything else is reported but never counted as a failure: 'slide' is a
// judgement call (sliding a phone is arguably cheating anyway), and the
// 'settle' gaps contain the act of putting the phone down.

class Sample {
  Sample(this.t, this.step, this.ax, this.ay, this.az, this.gx, this.gy, this.gz);

  final Duration t;
  final String step;
  final double ax, ay, az, gx, gy, gz;
}

List<Sample> load(String path) {
  final lines = File(path).readAsLinesSync();
  final out = <Sample>[];
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final p = line.split(',');
    if (p.length < 8) continue;
    out.add(Sample(
      Duration(milliseconds: int.parse(p[0])),
      p[1],
      double.parse(p[2]), double.parse(p[3]), double.parse(p[4]),
      double.parse(p[5]), double.parse(p[6]), double.parse(p[7]),
    ));
  }
  return out;
}

/// Replays the whole trace as one continuous stream — which is what the app
/// actually experiences — and attributes each catch to the step it happened
/// in.
///
/// Replaying a step in isolation does not work: the detector must first see
/// 1.2s of stillness to arm, and a step that opens mid-motion never arms, so
/// every pick-up would look like a miss. The trace supplies the stillness
/// between actions naturally, because the phone goes back on the table.
/// After a catch the detector is restarted so the next action is judged too.
class StepResult {
  var caught = false;
  String? reason;
  var armed = false;
  var peakAccel = 0.0;
  var peakGyro = 0.0;
}

Map<String, StepResult> replay(List<Sample> samples) {
  final results = <String, StepResult>{};
  var detector = PickupDetector()..start(samples.first.t);

  for (final s in samples) {
    final r = results.putIfAbsent(s.step, StepResult.new);

    final snap = detector.onAccelerometer(s.ax, s.ay, s.az, s.t);
    detector.onGyroscope(s.gx, s.gy, s.gz, s.t);

    r.peakAccel = math.max(r.peakAccel, snap.linearAcceleration);
    r.peakGyro = math.max(
      r.peakGyro,
      math.sqrt(s.gx * s.gx + s.gy * s.gy + s.gz * s.gz),
    );
    if (detector.state == DetectorState.armed) r.armed = true;

    if (detector.state == DetectorState.caught) {
      if (!r.caught) {
        r.caught = true;
        r.reason = detector.snapshot.reason?.name;
        r.armed = true;
      }
      // Re-arm so the rest of the sequence is still assessed.
      detector = PickupDetector()..start(s.t);
    }
  }

  return results;
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tools/analyse_trace.dart <trace.csv>');
    exit(2);
  }

  final samples = load(args.first);
  if (samples.isEmpty) {
    stderr.writeln('no samples in ${args.first}');
    exit(1);
  }

  // The recorder opens with stillness, so arm on that and then feed the whole
  // trace through continuously — this is what the app really experiences.
  final byStep = <String, List<Sample>>{};
  for (final s in samples) {
    byStep.putIfAbsent(s.step, () => []).add(s);
  }

  stdout.writeln('Trace: ${args.first}');
  stdout.writeln('${samples.length} samples over '
      '${(samples.last.t.inMilliseconds / 1000).toStringAsFixed(1)}s\n');

  stdout.writeln('Thresholds in use:');
  stdout.writeln('  pickUpAccelThreshold  ${DetectionConfig.pickUpAccelThreshold}');
  stdout.writeln('  pickUpGyroThreshold   ${DetectionConfig.pickUpGyroThreshold}');
  stdout.writeln('  sustainedMotionWindow ${DetectionConfig.sustainedMotionWindow.inMilliseconds}ms');
  stdout.writeln('  stillnessTolerance    ${DetectionConfig.stillnessTolerance}\n');

  var failures = 0;
  final results = replay(samples);

  stdout.writeln('${'step'.padRight(13)} ${'caught'.padRight(9)} '
      '${'expected'.padRight(10)} ${'armed'.padRight(6)} '
      'peak accel  peak gyro   verdict');

  // Report in recorded order, not hash order.
  final order = <String>[];
  for (final s in samples) {
    if (!order.contains(s.step)) order.add(s.step);
  }

  for (final step in order) {
    final r = results[step]!;
    final expected = shouldCatch.contains(step)
        ? 'catch'
        : mustNotCatch.contains(step)
            ? 'no catch'
            : 'either';

    String verdict;
    if (expected == 'either') {
      verdict = 'ok (judgement call)';
    } else if (shouldCatch.contains(step) && !r.caught) {
      verdict = r.armed
          ? 'MISSED — armed, but the lift stayed under the thresholds'
          : 'INCONCLUSIVE — never armed here, so it could not catch';
      failures++;
    } else if (mustNotCatch.contains(step) && r.caught) {
      verdict = 'FALSE POSITIVE — would wrongly blame someone';
      failures++;
    } else {
      verdict = 'ok';
    }

    stdout.writeln('${step.padRight(13)} '
        '${(r.caught ? (r.reason ?? 'yes') : 'no').padRight(9)} '
        '${expected.padRight(10)} '
        '${(r.armed ? 'yes' : 'no').padRight(6)} '
        '${r.peakAccel.toStringAsFixed(2).padLeft(10)}  '
        '${r.peakGyro.toStringAsFixed(2).padLeft(9)}   $verdict');
  }

  stdout.writeln();
  if (failures == 0) {
    stdout.writeln('PASS — the current thresholds suit this device.');
  } else {
    stdout.writeln('$failures problem(s). The peak columns show how much room '
        'there is: a threshold must sit above every "no catch" peak and below '
        'every "catch" peak.');
  }
  exit(failures == 0 ? 0 : 1);
}
