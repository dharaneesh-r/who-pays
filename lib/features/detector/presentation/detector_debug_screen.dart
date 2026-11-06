import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/detection_config.dart';
import '../../../core/theme/app_theme.dart';
import '../application/detector_service.dart';
import '../domain/detector_models.dart';

/// Live sensor read-out and detector state. Kept in the app behind a debug flag
/// permanently: when a group reports a false positive, this screen is the only
/// way to find out which threshold was wrong on their phone.
class DetectorDebugScreen extends ConsumerWidget {
  const DetectorDebugScreen({super.key});

  static const path = '/dev/detector';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(detectorServiceProvider);
    final snapshot =
        ref.watch(detectorSnapshotProvider).value ?? const DetectorSnapshot.idle();

    return Scaffold(
      appBar: AppBar(title: const Text('Sensor detector')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StateBadge(snapshot: snapshot),
              const SizedBox(height: 20),
              _Reading(
                label: 'Linear acceleration',
                value: snapshot.linearAcceleration,
                unit: 'm/s²',
                threshold: DetectionConfig.pickUpAccelThreshold,
              ),
              const SizedBox(height: 12),
              _Reading(
                label: 'Rotation rate',
                value: snapshot.rotationRate,
                unit: 'rad/s',
                threshold: DetectionConfig.pickUpGyroThreshold,
              ),
              const SizedBox(height: 24),
              _Hold(
                label: 'Stillness hold (to arm)',
                progress: snapshot.stillHoldProgress,
                color: AppTheme.safe,
              ),
              const SizedBox(height: 12),
              _Hold(
                label: 'Motion hold (to catch)',
                progress: snapshot.motionHoldProgress,
                color: AppTheme.danger,
              ),
              const Spacer(),
              if (snapshot.state == DetectorState.caught)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    '${snapshot.reason?.label ?? 'Caught'}'
                    '${snapshot.caughtAt != null ? ' after ${snapshot.caughtAt!.inMilliseconds} ms' : ''}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: service.start,
                child: const Text('PUT PHONE DOWN & WATCH'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: service.stop,
                child: const Text('STOP'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.snapshot});

  final DetectorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final (color, text) = switch (snapshot.state) {
      DetectorState.idle => (Colors.white24, 'IDLE'),
      DetectorState.settling => (AppTheme.accent, 'SETTLING — hold still'),
      DetectorState.armed => (AppTheme.safe, 'ARMED — don\'t touch it'),
      DetectorState.caught => (AppTheme.danger, 'CAUGHT'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({
    required this.label,
    required this.value,
    required this.unit,
    required this.threshold,
  });

  final String label;
  final double value;
  final String unit;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final over = value > threshold;
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          '${value.toStringAsFixed(2)} $unit',
          style: TextStyle(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w700,
            color: over ? AppTheme.danger : Colors.white,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '/ ${threshold.toStringAsFixed(1)}',
          style: const TextStyle(color: Colors.white38),
        ),
      ],
    );
  }
}

class _Hold extends StatelessWidget {
  const _Hold({
    required this.label,
    required this.progress,
    required this.color,
  });

  final String label;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 14,
            backgroundColor: Colors.white12,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
