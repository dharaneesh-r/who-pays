import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/purchase_service.dart';
import '../domain/entitlements.dart';

/// Shown when a free player runs out of rounds for the day.
///
/// One price, bought once, stated plainly. No countdown timers, no fake
/// discounts — the whole pitch is "you clearly play this, so own it".
/// Why the paywall appeared. The headline has to match what the player just
/// did — telling someone who tapped a locked pack that they are out of rounds
/// is simply wrong.
enum PaywallReason { outOfRounds, lockedPack, customStake }

extension on PaywallReason {
  String get headline => switch (this) {
        PaywallReason.outOfRounds => 'That\'s today\'s free rounds',
        PaywallReason.lockedPack => 'That pack is part of Pro',
        PaywallReason.customStake => 'Custom stakes are part of Pro',
      };
}

class PaywallSheet extends ConsumerWidget {
  const PaywallSheet({super.key, this.reason = PaywallReason.outOfRounds});

  final PaywallReason reason;

  static Future<void> show(
    BuildContext context, {
    PaywallReason reason = PaywallReason.outOfRounds,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PaywallSheet(reason: reason),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(purchaseServiceProvider.notifier);
    final text = Theme.of(context).textTheme;
    final price = service.priceOf(ProductIds.pro);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(reason.headline, style: text.headlineMedium),
            const SizedBox(height: 10),
            Text(
              'Unlock it once and keep it forever. No subscription.',
              style: text.bodyMedium?.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: 22),
            const _Perk('Unlimited rounds'),
            const _Perk('No ads'),
            const _Perk('Every Table Talk pack'),
            const _Perk('Full group stats and history'),
            const _Perk('Custom stakes'),
            const SizedBox(height: 26),
            FilledButton(
              onPressed: () {
                service.buy(ProductIds.pro);
                Navigator.of(context).pop();
              },
              child: Text(price.isEmpty ? 'UNLOCK' : 'UNLOCK · $price'),
            ),
            TextButton(
              onPressed: () {
                service.restore();
                Navigator.of(context).pop();
              },
              child: const Text('Restore a previous purchase'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Not now',
                style: TextStyle(color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.check_rounded, color: AppTheme.safe, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
