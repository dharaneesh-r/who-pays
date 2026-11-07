import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/monetisation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local/device_identity.dart';
import '../../../data/local/prefs_service.dart';
import '../../room/domain/join_link.dart';
import '../../paywall/application/consent_service.dart';
import '../../paywall/application/purchase_service.dart';
import '../../paywall/presentation/paywall_sheet.dart';
import '../../stats/application/reminder_service.dart';
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
    final reminders = ref.watch(remindersEnabledProvider).value ?? true;
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: reminders,
            onChanged: (value) async {
              if (value) {
                // Android 13+ needs permission before anything can be shown.
                await ref.read(reminderServiceProvider).requestPermission();
              }
              await ref.read(prefsServiceProvider).setRemindersEnabled(value);
              ref.invalidate(remindersEnabledProvider);

              final streak = await ref.read(streakProvider.future);
              await ref.read(reminderServiceProvider).refresh(streak);
            },
            title: const Text('Evening reminder'),
            subtitle: Text(
              reminders
                  ? 'A nudge at 7:30pm when your streak is about to end'
                  : 'No reminders',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ),
          const Divider(height: 36),
          // Required in the EEA/UK: people must be able to change their ad
          // consent after the first prompt. UMP reports this as unnecessary
          // everywhere else, so the row simply does not appear.
          FutureBuilder<bool>(
            future: ref.read(consentServiceProvider).privacyOptionsRequired(),
            builder: (context, snap) {
              if (snap.data != true) return const SizedBox.shrink();
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ad privacy options'),
                trailing: const Icon(Icons.tune, size: 18),
                onTap: ref.read(consentServiceProvider).showPrivacyOptions,
              );
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Privacy policy'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => launchUrl(
              Uri.parse('${JoinLink.host}/privacy'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const SizedBox(height: 8),
          // The privacy policy tells people they can ask for their usage data
          // to be deleted, and that this id is what identifies it. That
          // promise only works if the id is actually reachable.
          Text('Device ID', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'The only identifier we store. Send it to us if you want your '
            'usage data deleted.',
            style: text.bodyMedium?.copyWith(color: Colors.white38, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ref.watch(deviceIdProvider).when(
                loading: () => const SizedBox(height: 20),
                error: (_, _) => const SizedBox.shrink(),
                data: (id) => InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: id));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Device ID copied')),
                    );
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          id,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.5,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                      const Icon(Icons.copy, size: 16, color: Colors.white38),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
