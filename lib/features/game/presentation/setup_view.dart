import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cards/application/card_providers.dart';
import '../../paywall/application/purchase_service.dart';
import '../../paywall/presentation/paywall_sheet.dart';
import '../../stats/application/stats_providers.dart';
import '../application/game_controller.dart';
import '../domain/game_models.dart';

/// Choose a stake, a length and a conversation pack, then play.
///
/// Scrollable with the action pinned to the bottom: on a short screen the
/// three sections do not fit, and the start button must never be the thing
/// that scrolls out of reach.
class SetupView extends ConsumerStatefulWidget {
  const SetupView({super.key, this.onStart, this.actionLabel = 'PHONES DOWN'});

  /// Overridden when hosting a table: the same choices create a room instead
  /// of starting a solo round.
  final void Function(GameConfig config)? onStart;
  final String actionLabel;

  @override
  ConsumerState<SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends ConsumerState<SetupView> {
  static const _targets = <Duration?>[
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 60),
    null, // open-ended
  ];

  late final TextEditingController _custom = TextEditingController(
    text: ref.read(gameControllerProvider).config.customStake ?? '',
  );

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _start(GameConfig config) {
    // The free tier is counted in rounds per day. If the count has not loaded
    // yet, let them play — never block a round on a database read.
    final roundsToday = ref.read(roundsTodayProvider).value ?? 0;
    if (!ref.read(entitlementsProvider).canPlay(roundsToday: roundsToday)) {
      PaywallSheet.show(context);
      return;
    }
    widget.onStart == null
        ? ref.read(gameControllerProvider.notifier).start()
        : widget.onStart!(config);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameControllerProvider);
    final controller = ref.read(gameControllerProvider.notifier);
    final isPro = ref.watch(entitlementsProvider).isPro;
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            children: [
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
                  // Custom stakes are a Pro feature, so a free player sees it
                  // locked rather than missing — otherwise the paywall would
                  // be advertising something invisible.
                  ChoiceChip(
                    avatar: isPro ? null : const Icon(Icons.lock, size: 16),
                    label: const Text('something else'),
                    selected: state.config.stake == Stake.custom,
                    onSelected: (_) {
                      if (!isPro) {
                        PaywallSheet.show(context,
                            reason: PaywallReason.customStake);
                        return;
                      }
                      controller.setStake(
                        Stake.custom,
                        custom: _custom.text,
                      );
                    },
                  ),
                ],
              ),
              if (state.config.stake == Stake.custom) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _custom,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.none,
                  decoration: const InputDecoration(
                    labelText: 'The loser…',
                    hintText: 'walks the dog',
                    counterText: '',
                  ),
                  onChanged: (value) =>
                      controller.setStake(Stake.custom, custom: value),
                ),
              ],
              const SizedBox(height: 28),
              Text('For how long?', style: text.headlineMedium),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final target in _targets)
                    ChoiceChip(
                      label: Text(
                        target == null
                            ? 'Until someone cracks'
                            : '${target.inMinutes} min',
                      ),
                      selected: state.config.target == target,
                      onSelected: (_) => controller.setTarget(target),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              Text('Talk about…', style: text.headlineMedium),
              const SizedBox(height: 14),
              const _PackPicker(),
              const SizedBox(height: 24),
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
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: FilledButton(
            onPressed: () => _start(state.config),
            child: Text(widget.actionLabel),
          ),
        ),
      ],
    );
  }
}

class _PackPicker extends ConsumerWidget {
  const _PackPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packs = ref.watch(cardPacksProvider).value ?? const [];
    if (packs.isEmpty) return const SizedBox.shrink();

    final selected = ref.watch(selectedPackProvider);
    final entitlements = ref.watch(entitlementsProvider);

    // With nothing chosen the deck uses the first playable pack, so show that
    // as selected rather than leaving the row looking empty.
    final effective = selected ??
        packs.firstWhere((p) => entitlements.hasPack(p.id),
            orElse: () => packs.first).id;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final pack in packs)
          ChoiceChip(
            avatar: entitlements.hasPack(pack.id)
                ? null
                : const Icon(Icons.lock, size: 16),
            label: Text(pack.name),
            selected: effective == pack.id,
            onSelected: (_) {
              if (!entitlements.hasPack(pack.id)) {
                PaywallSheet.show(context,
                    reason: PaywallReason.lockedPack);
                return;
              }
              ref.read(selectedPackProvider.notifier).select(pack.id);
            },
          ),
      ],
    );
  }
}
