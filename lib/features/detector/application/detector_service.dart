import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/constants/detection_config.dart';
import '../domain/detector_models.dart';
import '../domain/pickup_detector.dart';

/// Wires the real device to [PickupDetector]: sensor streams in, snapshots out.
///
/// Also watches the app lifecycle, because the most common way to get caught is
/// not lifting the phone off the table — it is unlocking it and switching to
/// WhatsApp, which the accelerometer alone would miss.
class DetectorService {
  DetectorService() {
    _lifecycle = AppLifecycleListener(
      onInactive: () => _onLeftApp(),
      onHide: () => _onLeftApp(),
      onPause: () => _onLeftApp(),
    );
  }

  final _detector = PickupDetector();
  final _controller = StreamController<DetectorSnapshot>.broadcast();
  final _clock = Stopwatch();

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  late final AppLifecycleListener _lifecycle;

  Stream<DetectorSnapshot> get snapshots => _controller.stream;
  DetectorSnapshot get snapshot => _detector.snapshot;

  Duration get _now => _clock.elapsed;

  /// Start watching this phone. Call when the round begins.
  void start() {
    if (!_clock.isRunning) _clock.start();
    _emit(_detector.start(_now));

    _accelSub ??= accelerometerEventStream(
      samplingPeriod: DetectionConfig.samplingInterval,
    ).listen((e) => _emit(_detector.onAccelerometer(e.x, e.y, e.z, _now)));

    // A missing gyroscope is not an error — detection falls back to
    // acceleration only.
    _gyroSub ??= gyroscopeEventStream(
      samplingPeriod: DetectionConfig.samplingInterval,
    ).listen(
      (e) => _emit(_detector.onGyroscope(e.x, e.y, e.z, _now)),
      onError: (_) {},
      cancelOnError: false,
    );
  }

  /// Stop watching and clear any catch.
  void stop() {
    _accelSub?.cancel();
    _accelSub = null;
    _gyroSub?.cancel();
    _gyroSub = null;
    _clock.stop();
    _clock.reset();
    _emit(_detector.reset());
  }

  /// Catch this phone for a non-sensor reason.
  void trigger(CatchReason reason) => _emit(_detector.trigger(reason, _now));

  void _onLeftApp() {
    if (!_detector.snapshot.isWatching) return;
    _emit(_detector.trigger(CatchReason.leftApp, _now));
  }

  void _emit(DetectorSnapshot s) {
    if (!_controller.isClosed) _controller.add(s);
  }

  void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _lifecycle.dispose();
    _controller.close();
  }
}

final detectorServiceProvider = Provider.autoDispose<DetectorService>((ref) {
  final service = DetectorService();
  ref.onDispose(service.dispose);
  return service;
});

final detectorSnapshotProvider =
    StreamProvider.autoDispose<DetectorSnapshot>((ref) {
  return ref.watch(detectorServiceProvider).snapshots;
});
