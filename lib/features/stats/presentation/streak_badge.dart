import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/stats_providers.dart';

/// The streak, shown on the home screen.
///
/// Phrased as something to protect rather than something to start: "3 nights"
/// with a reminder that it ends tonight is what brings people back, whereas a
/// zero is just a scold, so nothing is shown until there is a streak.
class StreakBadge extends ConsumerWidget {
  const StreakBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(streakProvider).value;
    if (streak == null || !streak.isAlive) return const SizedBox.shrink();

    final nights = streak.current == 1 ? 'night' : 'nights';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_fire_department,
              color: AppTheme.accent, size: 22),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              streak.playedToday
                  ? '${streak.current} $nights in a row'
                  : '${streak.current} $nights — play tonight to keep it',
              style: const TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
