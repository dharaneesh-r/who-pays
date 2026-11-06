import 'package:flutter/material.dart';

/// Phase 1 builds this out: live accelerometer/gyroscope values and the
/// settling → armed → caught state machine, kept behind a debug flag forever
/// so detection can always be diagnosed on a real device.
class DetectorDebugScreen extends StatelessWidget {
  const DetectorDebugScreen({super.key});

  static const path = '/dev/detector';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sensor detector')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Phase 1: live sensor read-out and the pick-up state machine.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
