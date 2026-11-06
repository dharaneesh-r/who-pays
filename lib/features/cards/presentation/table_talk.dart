import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/card_providers.dart';
import '../domain/card_pack.dart';

/// One conversation prompt at a time while the round runs.
///
/// Rotates slowly — a question every 45 seconds. Fast enough that a dead
/// conversation gets rescued, slow enough that a good one is never interrupted.
class TableTalk extends ConsumerStatefulWidget {
  const TableTalk({super.key});

  static const rotation = Duration(seconds: 45);

  @override
  ConsumerState<TableTalk> createState() => _TableTalkState();
}

class _TableTalkState extends ConsumerState<TableTalk> {
  Timer? _timer;
  PromptDeck? _deck;
  String? _prompt;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(TableTalk.rotation, (_) => _advance());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _advance() {
    if (!mounted) return;
    setState(() => _prompt = _deck?.next());
  }

  @override
  Widget build(BuildContext context) {
    final deck = ref.watch(promptDeckProvider);
    if (deck == null) return const SizedBox.shrink();

    if (!identical(deck, _deck)) {
      _deck = deck;
      _prompt ??= deck.current;
    }

    final prompt = _prompt ?? deck.current;
    if (prompt == null) return const SizedBox.shrink();

    return GestureDetector(
      // Tapping the screen is allowed — it is picking the phone *up* that
      // loses. So anyone can skip a dud question.
      onTap: _advance,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Text(
              'TALK ABOUT THIS',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                prompt,
                key: ValueKey(prompt),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
