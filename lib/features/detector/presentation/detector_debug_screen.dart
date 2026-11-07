import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/detection_config.dart';
import '../../../core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

import '../application/detector_service.dart';
import '../domain/detector_models.dart';
import 'trace_screen.dart';

/// Live sensor read-out and detector state. Kept in the app behind a debug flag
/// permanently: when a group reports a false positive, this screen is the only
/// way to find out which threshold was wrong on their phone.
class DetectorDebugScreen extends ConsumerStatefulWidget {
  const DetectorDebugScreen({super.key});

  static const path = '/dev/detector';

  @override
  ConsumerState<DetectorDebugScreen> createState() =>
      _DetectorDebugScreenState();
}

class _DetectorDebugScreenState extends ConsumerState<DetectorDebugScreen> {
  // The highest readings seen since the last reset.
  //
  // Live numbers are useless for setting a threshold: the peak of a table
  // thump lasts a few milliseconds and is gone before anyone can read it off
  // the screen. Holding the maximum turns "watch the numbers" into two
  // numbers somebody can actually write down — the worst a knock produces,
  // and the least a real pick-up produces. The threshold has to sit between
  // them.
  double _peakAccel = 0;
  double _peakGyro = 0;

  void _reset() => setState(() {
        _peakAccel = 0;
        _peakGyro = 0;
      });

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(detectorServiceProvider);
    final snapshot =
        ref.watch(detectorSnapshotProvider).value ?? const DetectorSnapshot.idle();

    if (snapshot.linearAcceleration > _peakAccel ||
        snapshot.rotationRate > _peakGyro) {
      // Painting is not the place to change state, so defer it a frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _peakAccel = math.max(_peakAccel, snapshot.linearAcceleration);
          _peakGyro = math.max(_peakGyro, snapshot.rotationRate);
        });
      });
    }

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
              const SizedBox(height: 18),
              _PeakCard(accel: _peakAccel, gyro: _peakGyro),
              const SizedBox(height: 18),
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
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _reset,
                child: const Text('RESET PEAKS'),
              ),
              const SizedBox(height: 10),
              // Capturing labelled sensor data beats reading these numbers off
              // the screen: the thresholds can then be fitted to what the
              // device actually does.
              OutlinedButton(
                onPressed: () => context.push(TraceScreen.path),
                child: const Text('RECORD A TRACE'),
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

/// The two numbers that decide every threshold, held so they can be read.
class _PeakCard extends StatelessWidget {
  const _PeakCard({required this.accel, required this.gyro});

  final double accel;
  final double gyro;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.10),
        border: Border.all(color: AppTheme.accent, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            'PEAK SINCE RESET',
            style: TextStyle(
              color: AppTheme.accent,
              fontSize: 12,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Peak(label: 'accel', value: accel, unit: 'm/s²'),
              _Peak(label: 'rotation', value: gyro, unit: 'rad/s'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Peak extends StatelessWidget {
  const _Peak({required this.label, required this.value, required this.unit});

  final String label;
  final double value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value.toStringAsFixed(2),
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        Text('$label ($unit)',
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
      ],
    );
  }
}
