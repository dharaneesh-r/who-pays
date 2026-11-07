import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/constants/detection_config.dart';

/// One step of the guided capture. Each labels its samples, so the resulting
/// file is ground truth rather than an undifferentiated blob of numbers.
class TraceStep {
  const TraceStep(this.label, this.instruction, this.seconds);

  final String label;
  final String instruction;
  final int seconds;
}

/// Records real sensor data while the phone is put through a known sequence.
///
/// Detection thresholds cannot honestly be tuned against a simulation — a
/// Bosch BMI160 on a wooden table behaves nothing like an idealised model.
/// This captures what actually happens, labelled by what the person was
/// doing, so the numbers can be fitted to reality and re-checked later
/// without needing the phone again.
class TraceRecorder {
  StreamSubscription<AccelerometerEvent>? _accel;
  StreamSubscription<GyroscopeEvent>? _gyro;
  Timer? _stepTimer;
  Timer? _tick;

  final _rows = <String>[];
  final _clock = Stopwatch();

  double _gx = 0, _gy = 0, _gz = 0;
  double _rx = 0, _ry = 0, _rz = 0;

  int _stepIndex = 0;
  final _progress = StreamController<TraceProgress>.broadcast();

  Stream<TraceProgress> get progress => _progress.stream;

  /// The sequence. Deliberately opens and closes with stillness, so drift in
  /// the gravity estimate across the whole run is measurable.
  static const steps = <TraceStep>[
    TraceStep('still', 'Put it face down and leave it alone', 8),
    TraceStep('thump', 'Thump the table hard, about 5 times', 10),
    TraceStep('knock', 'Knock the table leg, or lean on the table', 6),
    TraceStep('slide', 'Slide the phone across the table', 6),
    // Each lift gets its own settling gap. The detector needs an unbroken
    // stretch of stillness to arm, and without these the second and third
    // lifts are never armed, so they prove nothing.
    TraceStep('settle', 'Leave it face down — do not touch it', 4),
    TraceStep('lift_slow', 'Lift it as slowly and gently as you can', 5),
    TraceStep('settle_2', 'Put it back down and leave it', 4),
    TraceStep('lift_normal', 'Pick it up normally', 5),
    TraceStep('settle_3', 'Put it back down and leave it', 4),
    TraceStep('flip', 'Flip it face up', 5),
    TraceStep('still_end', 'Put it face down and leave it alone', 6),
  ];

  static Duration get totalDuration =>
      Duration(seconds: steps.fold(0, (sum, s) => sum + s.seconds));

  bool get isRecording => _clock.isRunning;

  Future<void> start() async {
    if (isRecording) return;

    _rows
      ..clear()
      ..add('t_ms,step,ax,ay,az,gx,gy,gz');
    _stepIndex = 0;
    _clock
      ..reset()
      ..start();

    _accel = accelerometerEventStream(
      samplingPeriod: DetectionConfig.samplingInterval,
    ).listen((e) {
      _gx = e.x;
      _gy = e.y;
      _gz = e.z;
      _write();
    });

    _gyro = gyroscopeEventStream(
      samplingPeriod: DetectionConfig.samplingInterval,
    ).listen(
      (e) {
        _rx = e.x;
        _ry = e.y;
        _rz = e.z;
      },
      onError: (_) {},
      cancelOnError: false,
    );

    // Without this the sample count only refreshes when a step changes, so
    // the first eight seconds read "0 samples" and the screen looks dead.
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => _emit());

    _emit();
    _scheduleStep();
  }

  void _scheduleStep() {
    _stepTimer?.cancel();
    if (_stepIndex >= steps.length) return;

    _stepTimer = Timer(Duration(seconds: steps[_stepIndex].seconds), () {
      _stepIndex++;
      if (_stepIndex >= steps.length) {
        _tick?.cancel();
        _emit(done: true);
        return;
      }
      _emit();
      _scheduleStep();
    });
  }

  void _write() {
    if (!isRecording || _stepIndex >= steps.length) return;
    _rows.add('${_clock.elapsedMilliseconds},${steps[_stepIndex].label},'
        '${_gx.toStringAsFixed(4)},${_gy.toStringAsFixed(4)},'
        '${_gz.toStringAsFixed(4)},${_rx.toStringAsFixed(4)},'
        '${_ry.toStringAsFixed(4)},${_rz.toStringAsFixed(4)}');
  }

  void _emit({bool done = false}) {
    if (_progress.isClosed) return;
    _progress.add(TraceProgress(
      stepIndex: _stepIndex,
      done: done,
      samples: _rows.length - 1,
    ));
  }

  /// Stops and writes the file. Saved to the app's external files directory,
  /// which `adb pull` can read without the app being debuggable.
  Future<String?> stop() async {
    _tick?.cancel();
    _stepTimer?.cancel();
    await _accel?.cancel();
    await _gyro?.cancel();
    _accel = null;
    _gyro = null;
    _clock.stop();

    if (_rows.length < 2) return null;

    try {
      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/trace_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      await file.writeAsString(_rows.join('\n'));
      return file.path;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _tick?.cancel();
    _stepTimer?.cancel();
    _accel?.cancel();
    _gyro?.cancel();
    _progress.close();
  }
}

class TraceProgress {
  const TraceProgress({
    required this.stepIndex,
    required this.done,
    required this.samples,
  });

  final int stepIndex;
  final bool done;
  final int samples;

  TraceStep? get step =>
      stepIndex < TraceRecorder.steps.length
          ? TraceRecorder.steps[stepIndex]
          : null;
}

final traceRecorderProvider = Provider<TraceRecorder>((ref) {
  final recorder = TraceRecorder();
  ref.onDispose(recorder.dispose);
  return recorder;
});
