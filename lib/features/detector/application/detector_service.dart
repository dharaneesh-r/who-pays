import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/constants/detection_config.dart';
import '../domain/detector_models.dart';
import '../domain/pickup_detector.dart';

/// What the game needs from a detector, so a test can supply one.
///
/// The real implementation talks to the phone's sensors; a test drives
/// [snapshots] directly and never touches a plugin.
abstract interface class Detector {
  Stream<DetectorSnapshot> get snapshots;
  DetectorSnapshot get snapshot;
  void start();
  void stop();
  void trigger(CatchReason reason);
  void dispose();
}

/// Wires the real device to [PickupDetector]: sensor streams in, snapshots out.
///
/// Also watches the app lifecycle, because the most common way to get caught is
/// not lifting the phone off the table — it is unlocking it and switching to
/// WhatsApp, which the accelerometer alone would miss.
class DetectorService implements Detector {
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

  @override
  Stream<DetectorSnapshot> get snapshots => _controller.stream;

  @override
  DetectorSnapshot get snapshot => _detector.snapshot;

  Duration get _now => _clock.elapsed;

  /// Start watching this phone. Call when the round begins.
  @override
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
  @override
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
  @override
  void trigger(CatchReason reason) => _emit(_detector.trigger(reason, _now));

  void _onLeftApp() {
    if (!_detector.snapshot.isWatching) return;
    _emit(_detector.trigger(CatchReason.leftApp, _now));
  }

  void _emit(DetectorSnapshot s) {
    if (!_controller.isClosed) _controller.add(s);
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _lifecycle.dispose();
    _controller.close();
  }
}

/// App-lifetime singleton: it owns the sensor subscriptions and the lifecycle
/// listener, so it must not be torn down and rebuilt as screens come and go.
final detectorServiceProvider = Provider<Detector>((ref) {
  final service = DetectorService();
  ref.onDispose(service.dispose);
  return service;
});

final detectorSnapshotProvider = StreamProvider<DetectorSnapshot>((ref) {
  return ref.watch(detectorServiceProvider).snapshots;
});
