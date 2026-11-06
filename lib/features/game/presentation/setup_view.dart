import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/game_controller.dart';
import '../domain/game_models.dart';

/// Two decisions, then play. Anything more and the table loses interest.
class SetupView extends ConsumerWidget {
  const SetupView({super.key});

  static const _targets = <Duration?>[
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 60),
    null, // open-ended
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameControllerProvider);
    final controller = ref.read(gameControllerProvider.notifier);
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Text('The loser…', style: text.headlineMedium),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final stake in Stake.values)
                if (stake != Stake.custom)
                  ChoiceChip(
                    label: Text(stake.label),
                    selected: state.config.stake == stake,
                    onSelected: (_) => controller.setStake(stake),
                  ),
            ],
          ),
          const SizedBox(height: 32),
          Text('For how long?', style: text.headlineMedium),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final target in _targets)
                ChoiceChip(
                  label: Text(
                    target == null ? 'Until someone cracks' : '${target.inMinutes} min',
                  ),
                  selected: state.config.target == target,
                  onSelected: (_) => controller.setTarget(target),
                ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text('1. Everyone puts their phone face down'),
                const SizedBox(height: 6),
                const Text('2. Nobody touches it'),
                const SizedBox(height: 6),
                Text(
                  '3. First to crack ${state.config.stakeText}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: controller.start,
            child: const Text('PHONES DOWN'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
