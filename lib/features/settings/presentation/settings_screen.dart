import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/monetisation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local/prefs_service.dart';
import '../../paywall/application/purchase_service.dart';
import '../../paywall/presentation/paywall_sheet.dart';
import '../../stats/application/stats_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  static const path = '/settings';

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();
  bool _nameLoaded = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    await ref.read(prefsServiceProvider).setPlayerName(_name.text);
    // Stats are keyed by name, so a rename changes what the leaderboard shows.
    ref.invalidate(playerNameProvider);
    ref.invalidate(hasPlayerNameProvider);
    ref.read(statsRevisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    final entitlements = ref.watch(entitlementsProvider);
    final siren = ref.watch(sirenEnabledProvider).value ?? true;
    final text = Theme.of(context).textTheme;

    ref.watch(playerNameProvider).whenData((name) {
      if (!_nameLoaded) {
        _nameLoaded = true;
        if (name != PrefsService.defaultPlayerName) _name.text = name;
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          const SizedBox(height: 8),
          Text('Your name', style: text.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: 24,
            decoration: const InputDecoration(
              hintText: 'What the table calls you',
              counterText: '',
            ),
            onChanged: (_) => _saveName(),
            onSubmitted: (_) => _saveName(),
          ),
          Text(
            'Used on the leaderboard and when you join a table. '
            'Without it your own rounds are just saved as "You".',
            style: text.bodyMedium?.copyWith(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 28),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: siren,
            onChanged: (value) async {
              await ref.read(prefsServiceProvider).setSirenEnabled(value);
              ref.invalidate(sirenEnabledProvider);
            },
            title: const Text('Siren'),
            subtitle: Text(
              siren
                  ? 'Loud alarm when someone cracks'
                  : 'Silent — the phone still buzzes',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
          // Nothing to sell on an ads-only launch, so the whole section goes.
          if (!Monetisation.proEnabled) ...[
            const SizedBox(height: 20),
            Text(
              'Everything is unlocked and free. The app is paid for by a '
              'single ad after a round.',
              style: text.bodyMedium?.copyWith(color: Colors.white38, fontSize: 13),
            ),
          ] else ...[
          const Divider(height: 36),
          Text('Pro', style: text.titleMedium),
          const SizedBox(height: 8),
          if (entitlements.isPro)
            const Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.safe, size: 22),
                SizedBox(width: 10),
                Expanded(child: Text('Unlocked. Thank you.')),
              ],
            )
          else ...[
            Text(
              'Unlimited rounds, no ads, every Table Talk pack, '
              'custom stakes and full stats. One payment, kept forever.',
              style: text.bodyMedium?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => PaywallSheet.show(context),
              child: const Text('UNLOCK PRO'),
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () async {
              await ref.read(purchaseServiceProvider.notifier).restore();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Checked the store for earlier purchases'),
                ),
              );
            },
            child: const Text('RESTORE PURCHASES'),
          ),
          const SizedBox(height: 10),
          Text(
            'Restore brings back a purchase after a reinstall or on a new '
            'phone. Purchases only work on a build installed from Google Play.',
            style: text.bodyMedium?.copyWith(color: Colors.white38, fontSize: 13),
          ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
