import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/local/prefs_service.dart';
import '../../../data/remote/supabase_init.dart';
import '../../duel/application/duel_session.dart';
import '../../duel/presentation/duel_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../detector/presentation/detector_debug_screen.dart';
import '../../game/presentation/game_screen.dart';
import '../../room/application/room_session.dart';
import '../../room/presentation/host_setup_screen.dart';
import '../../room/presentation/join_room_screen.dart';
import '../../room/presentation/room_lobby_screen.dart';
import '../../stats/presentation/stats_screen.dart';
import '../../stats/presentation/streak_badge.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const path = '/';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final online = ref.watch(supabaseReadyProvider);
    final hasName = ref.watch(hasPlayerNameProvider).value ?? true;
    final rejoin = ref.watch(rejoinableRoomProvider).value;
    final inDuel = ref.watch(duelSessionProvider).inDuel;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // Long-press the title to reach the sensor read-out. It has to
              // work in release builds too — thresholds can only be tuned on
              // real hardware, and testers run release APKs. Hidden rather
              // than removed, so it never confuses an ordinary player.
              GestureDetector(
                onLongPress: () => context.push(DetectorDebugScreen.path),
                child: Text('WHO\nPAYS?', style: text.displayMedium),
              ),
              const SizedBox(height: 12),
              Text(
                'Phones face down. First one to pick up loses.',
                style: text.bodyMedium?.copyWith(color: Colors.white60),
              ),
              const Spacer(),
              // Offered only when the saved table still exists, so a player
              // whose app was killed mid-round can get straight back in.
              if (rejoin != null) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.safe,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () async {
                    await ref.read(roomSessionProvider.notifier).rejoinLast();
                    if (!context.mounted) return;
                    if (ref.read(roomSessionProvider).inRoom) {
                      context.push(RoomLobbyScreen.path);
                    }
                  },
                  icon: const Icon(Icons.replay),
                  label: Text('REJOIN $rejoin'),
                ),
                const SizedBox(height: 12),
              ],
              const StreakBadge(),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.push(HostSetupScreen.path),
                child: const Text('HOST A TABLE'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.push(JoinRoomScreen.path),
                child: const Text('JOIN WITH CODE'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.push(GameScreen.path),
                child: const Text('JUST ME'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.push(DuelScreen.path),
                child: Text(inDuel ? "TODAY'S DUEL" : 'FOCUS DUEL'),
              ),
              if (!online) ...[
                const SizedBox(height: 10),
                Text(
                  'Offline — only solo rounds work right now',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium
                      ?.copyWith(color: Colors.white38, fontSize: 13),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => context.push(StatsScreen.path),
                    child: const Text('My record'),
                  ),
                  const Text('·', style: TextStyle(color: Colors.white24)),
                  TextButton(
                    onPressed: () => context.push(SettingsScreen.path),
                    // A player with no name saved shows up on the leaderboard
                    // as "You", so nudge them once rather than silently
                    // collecting meaningless stats.
                    child: Text(
                      hasName ? 'Settings' : 'Set your name',
                      style: TextStyle(
                        color: hasName ? null : AppTheme.accent,
                        fontWeight: hasName ? null : FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (kDebugMode)
                TextButton(
                  onPressed: () => context.push(DetectorDebugScreen.path),
                  child: const Text('Dev · sensor detector'),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
