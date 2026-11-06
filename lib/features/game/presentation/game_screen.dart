import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/game_controller.dart';
import '../domain/game_models.dart';
import 'play_view.dart';
import 'result_view.dart';
import 'setup_view.dart';

/// One screen for the whole round. The phase drives what is shown, so there is
/// no navigation to get wrong while six phones are face down on a table.
class GameScreen extends ConsumerWidget {
  const GameScreen({super.key});

  static const path = '/game';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(gameControllerProvider).phase;

    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: switch (phase) {
            RoundPhase.setup => const SetupView(),
            RoundPhase.settling || RoundPhase.running => const PlayView(),
            RoundPhase.finished => const ResultView(),
          },
        ),
      ),
    );
  }
}
