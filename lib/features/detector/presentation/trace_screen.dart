import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../application/trace_recorder.dart';

/// Guided sensor capture.
///
/// Thresholds tuned against a simulation are guesses. This walks the phone
/// through a known sequence — thump, slide, lift, flip — and labels every
/// sample with what was happening, so the numbers can be fitted to a real
/// device on a real table and re-checked later without it.
class TraceScreen extends ConsumerStatefulWidget {
  const TraceScreen({super.key});

  static const path = '/dev/trace';

  @override
  ConsumerState<TraceScreen> createState() => _TraceScreenState();
}

class _TraceScreenState extends ConsumerState<TraceScreen> {
  TraceProgress? _progress;
  String? _savedPath;
  bool _running = false;

  @override
  void dispose() {
    // Leaving the lock on would quietly drain the battery after the screen is
    // gone.
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _start() async {
    // The sequence runs for over a minute with no touches, and most phones
    // sleep after thirty seconds — the instructions have to stay visible.
    await WakelockPlus.enable();
    final recorder = ref.read(traceRecorderProvider);
    setState(() {
      _running = true;
      _savedPath = null;
      _progress = null;
    });

    recorder.progress.listen((p) {
      if (!mounted) return;
      setState(() => _progress = p);
      if (p.done) _finish();
    });

    await recorder.start();
  }

  Future<void> _finish() async {
    await WakelockPlus.disable();
    final path = await ref.read(traceRecorderProvider).stop();
    if (!mounted) return;
    setState(() {
      _running = false;
      _savedPath = path;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final step = _progress?.step;
    final total = TraceRecorder.steps.length;
    final index = _progress?.stepIndex ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Record a trace')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              if (!_running && _savedPath == null) ...[
                Text('Before you start', style: text.headlineMedium),
                const SizedBox(height: 12),
                Text(
                  'This records ${TraceRecorder.totalDuration.inSeconds} seconds '
                  'of real sensor data while you put the phone through a set '
                  'sequence. Follow each instruction as it appears.\n\n'
                  'Do it on the kind of table you would actually play on. '
                  'Keep the phone plugged in.',
                  style: text.bodyMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                for (final s in TraceRecorder.steps)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text(
                            '${s.seconds}s',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            s.instruction,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _start,
                  child: const Text('START RECORDING'),
                ),
              ],
              if (_running) ...[
                const Spacer(),
                Text(
                  'STEP ${index + 1} OF $total',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.accent,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  step?.instruction ?? '',
                  textAlign: TextAlign.center,
                  style: text.headlineMedium,
                ),
                const SizedBox(height: 28),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : (index + 1) / total,
                    minHeight: 12,
                    backgroundColor: Colors.white12,
                    valueColor:
                        const AlwaysStoppedAnimation(AppTheme.accent),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '${_progress?.samples ?? 0} samples',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: _finish,
                  child: const Text('STOP EARLY'),
                ),
              ],
              if (_savedPath != null) ...[
                const Spacer(),
                const Icon(Icons.check_circle,
                    color: AppTheme.safe, size: 56),
                const SizedBox(height: 16),
                Text(
                  'Saved',
                  textAlign: TextAlign.center,
                  style: text.headlineMedium?.copyWith(color: AppTheme.safe),
                ),
                const SizedBox(height: 12),
                Text(
                  '${_progress?.samples ?? 0} samples written to:',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: Colors.white60),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _savedPath!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.white38,
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _start,
                  child: const Text('RECORD ANOTHER'),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
