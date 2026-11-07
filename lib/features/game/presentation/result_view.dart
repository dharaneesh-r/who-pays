import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/feedback/alarm_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../paywall/application/ads_service.dart';
import '../../room/application/room_session.dart';
import '../../room/presentation/live_standings.dart';
import '../../share/application/share_service.dart';
import '../../detector/domain/detector_models.dart';
import '../application/game_controller.dart';
import '../domain/game_models.dart';

/// Who owes what. Solo rounds only know about this phone; at a table the room
/// decides, because the loser is whoever was first — not everyone who cracked.
String _verdict({
  required bool caught,
  required String stakeText,
  required String stakeTextYou,
  required String? loserName,
  required bool youLost,
}) {
  if (loserName == null) {
    return caught ? 'So you $stakeTextYou.' : 'Somebody else $stakeText.';
  }
  return youLost
      ? 'You cracked first — you $stakeTextYou.'
      : '$loserName $stakeText.';
}

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

    // At a table, being caught is not the same as losing — the loser is
    // whoever cracked *first*, which only the room knows.
    final session = ref.watch(roomSessionProvider);
    final loser = session.snapshot?.loser;
    final loserName = loser?.name;
    final youLost = loser != null && loser.deviceId == session.deviceId;

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
              _verdict(
                caught: caught,
                stakeText: state.config.stakeText,
                stakeTextYou: state.config.stakeTextYou,
                loserName: loserName,
                youLost: youLost,
              ),
              textAlign: TextAlign.center,
              style: text.titleMedium,
            ),
          ),
          if (session.inRoom) ...[
            const SizedBox(height: 20),
            const LiveStandings(),
          ],
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
          OutlinedButton.icon(
            onPressed: result == null
                ? null
                : () => ref.read(shareServiceProvider).shareResult(
                      config: state.config,
                      result: result,
                      loserName: loserName,
                      standings: session.snapshot?.standings ?? const [],
                    ),
            icon: const Icon(Icons.ios_share),
            label: const Text('SHARE THE DAMAGE'),
          ),
          const SizedBox(height: 12),
          // The ad runs when leaving the result, never on arrival: an
          // interstitial landing on top of the siren would be unbearable, and
          // an ad during a round would cover the clock the table is watching.
          FilledButton(
            onPressed: () async {
              await ref.read(adsServiceProvider).maybeShowOnResult();
              controller.start();
            },
            child: const Text('PLAY AGAIN'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              controller.reset();
              await ref.read(adsServiceProvider).maybeShowOnResult();
              if (context.mounted && context.canPop()) context.pop();
            },
            child: const Text('DONE'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
