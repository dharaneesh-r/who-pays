import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/remote/supabase_init.dart';
import '../../detector/presentation/detector_debug_screen.dart';
import '../../game/presentation/game_screen.dart';
import '../../room/presentation/host_setup_screen.dart';
import '../../room/presentation/join_room_screen.dart';
import '../../stats/presentation/stats_screen.dart';
import '../../stats/presentation/streak_badge.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const path = '/';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final online = ref.watch(supabaseReadyProvider);

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
                child: Text('WHO\nPAYS?', style: text.displayLarge),
              ),
              const SizedBox(height: 12),
              Text(
                'Phones face down. First one to pick up loses.',
                style: text.bodyMedium?.copyWith(color: Colors.white60),
              ),
              const Spacer(),
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
              TextButton(
                onPressed: () => context.push(StatsScreen.path),
                child: const Text('My record'),
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
