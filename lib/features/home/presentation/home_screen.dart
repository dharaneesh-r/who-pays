import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../detector/presentation/detector_debug_screen.dart';
import '../../game/presentation/game_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const path = '/';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text('WHO\nPAYS?', style: text.displayLarge, textAlign: TextAlign.left),
              const SizedBox(height: 12),
              Text(
                'Phones face down. First one to pick up loses.',
                style: text.bodyMedium?.copyWith(color: Colors.white60),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => context.push(GameScreen.path),
                child: const Text('START A GAME'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: null, // Phase 5
                child: const Text('JOIN WITH CODE'),
              ),
              const SizedBox(height: 24),
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
