import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/feedback/alarm_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../detector/domain/detector_models.dart';
import '../application/game_controller.dart';
import '../domain/game_models.dart';

class ResultView extends ConsumerWidget {
  const ResultView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameControllerProvider);
    final controller = ref.read(gameControllerProvider.notifier);
    final text = Theme.of(context).textTheme;
    final result = state.result;

    final caught = result?.outcome == RoundOutcome.caught;
    final color = caught ? AppTheme.danger : AppTheme.safe;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Text(
            caught ? 'CAUGHT' : 'YOU MADE IT',
            textAlign: TextAlign.center,
            style: text.displayLarge?.copyWith(fontSize: 56, color: color),
          ),
          const SizedBox(height: 16),
          if (caught)
            Text(
              '${result!.reason?.label ?? 'Picked the phone up'}\n'
              'after ${formatClock(result.lasted)}',
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(color: Colors.white70),
            )
          else
            Text(
              'You lasted ${formatClock(result?.lasted ?? Duration.zero)}\n'
              'without touching your phone',
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(color: Colors.white70),
            ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              caught
                  ? 'So you ${state.config.stakeText}.'
                  : 'Somebody else ${state.config.stakeText}.',
              textAlign: TextAlign.center,
              style: text.titleMedium,
            ),
          ),
          const Spacer(),
          // The siren loops until someone acknowledges it. That is deliberate —
          // but it needs one obvious way to stop without leaving the screen.
          if (caught) ...[
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
              onPressed: ref.read(alarmServiceProvider).silence,
              child: const Text('SILENCE THE SIREN'),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: controller.start,
            child: const Text('PLAY AGAIN'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              controller.reset();
              if (context.canPop()) context.pop();
            },
            child: const Text('DONE'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
