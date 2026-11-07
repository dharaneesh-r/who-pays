import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../cards/presentation/table_talk.dart';
import '../../room/application/room_session.dart';
import '../../room/presentation/live_standings.dart';
import '../application/game_controller.dart';
import '../domain/game_models.dart';

/// The screen the whole table stares at. Two states: still settling, or
/// running. Everything is oversized because it is read from across a table.
class PlayView extends ConsumerWidget {
  const PlayView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameControllerProvider);
    final controller = ref.read(gameControllerProvider.notifier);
    final text = Theme.of(context).textTheme;

    final settling = state.phase == RoundPhase.settling;
    final inRoom = ref.watch(roomSessionProvider).inRoom;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Text(
            settling ? 'PUT IT DOWN' : 'DON\'T TOUCH IT',
            textAlign: TextAlign.center,
            style: text.headlineMedium?.copyWith(
              color: settling ? AppTheme.accent : AppTheme.safe,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          if (settling)
            Column(
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: state.detector.stillHoldProgress,
                    strokeWidth: 10,
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Hold still — the round starts\nwhen the phone settles',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: Colors.white60),
                ),
              ],
            )
          else
            Column(
              children: [
                Text(
                  formatClock(state.elapsed),
                  style: text.displayLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  state.config.target == null
                      ? 'Until someone cracks'
                      : 'of ${state.config.target!.inMinutes} min',
                  style: text.bodyMedium?.copyWith(color: Colors.white54),
                ),
                if (state.targetProgress != null) ...[
                  const SizedBox(height: 22),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: state.targetProgress,
                      minHeight: 10,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(AppTheme.safe),
                    ),
                  ),
                ],
              ],
            ),
          const Spacer(),
          if (!settling) ...[
            const TableTalk(),
            const SizedBox(height: 16),
          ],
          if (inRoom) ...[
            const LiveStandings(),
            const SizedBox(height: 20),
          ],
          Text(
            'Loser ${state.config.stakeText}',
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 20),
          // Deliberately an understated text button: giving up should feel
          // like a worse option than just leaving the phone alone.
          TextButton(
            onPressed: controller.concede,
            child: Text(
              'I give up — I ${state.config.stakeTextYou}',
              style: const TextStyle(color: Colors.white38),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
