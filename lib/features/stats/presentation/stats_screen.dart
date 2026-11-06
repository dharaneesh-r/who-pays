import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/local/round_dao.dart';
import '../../detector/domain/detector_models.dart';
import '../../game/domain/game_models.dart';
import '../application/stats_providers.dart';
import '../domain/tally.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  static const path = '/stats';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tallies = ref.watch(talliesProvider);
    final rounds = ref.watch(recentRoundsProvider);
    final best = ref.watch(personalBestProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Record')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          best.maybeWhen(
            data: (value) => _BestCard(best: value),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: 24),
          Text('Last 30 days', style: text.headlineMedium),
          const SizedBox(height: 12),
          tallies.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Text('Could not read your history.'),
            data: (data) {
              if (data.isEmpty) {
                return const Text(
                  'No rounds yet. Play one and your record shows up here.',
                  style: TextStyle(color: Colors.white54),
                );
              }
              final line = headline(data);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (line != null) ...[
                    Text(
                      line,
                      style: text.titleMedium?.copyWith(color: AppTheme.danger),
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (final tally in data) _TallyRow(tally: tally),
                ],
              );
            },
          ),
          const SizedBox(height: 28),
          Text('Recent rounds', style: text.headlineMedium),
          const SizedBox(height: 12),
          rounds.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (data) => Column(
              children: [for (final round in data.take(20)) _RoundRow(round: round)],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _BestCard extends StatelessWidget {
  const _BestCard({required this.best});

  final Duration best;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.safe.withValues(alpha: 0.12),
        border: Border.all(color: AppTheme.safe.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text('Your longest round', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          Text(
            formatClock(best),
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _TallyRow extends StatelessWidget {
  const _TallyRow({required this.tally});

  final PlayerTally tally;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tally.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '${tally.firstCracks} / ${tally.rounds}',
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 56,
            child: Text(
              '${(tally.crackRate * 100).round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: tally.crackRate > 0.5 ? AppTheme.danger : Colors.white54,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundRow extends StatelessWidget {
  const _RoundRow({required this.round});

  final StoredRound round;

  @override
  Widget build(BuildContext context) {
    final caught = round.outcome == RoundOutcome.caught;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(
            caught ? Icons.close_rounded : Icons.check_rounded,
            size: 20,
            color: caught ? AppTheme.danger : AppTheme.safe,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              caught
                  ? (round.reason?.label ?? 'Caught')
                  : 'Survived the round',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          Text(
            formatClock(round.lasted),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
