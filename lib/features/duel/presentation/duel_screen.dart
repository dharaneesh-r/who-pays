import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../game/domain/game_models.dart';
import '../../game/presentation/game_screen.dart';
import '../application/duel_session.dart';
import '../domain/duel_models.dart';

/// Today's duel board.
///
/// The whole point is that nobody has to be free at the same time: you play a
/// round whenever you like, and the longest one today wins the day.
class DuelScreen extends ConsumerStatefulWidget {
  const DuelScreen({super.key});

  static const path = '/duel';

  @override
  ConsumerState<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends ConsumerState<DuelScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(duelSessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(state.board?.duel.name ?? 'Focus Duel'),
        actions: [
          if (state.inDuel)
            IconButton(
              tooltip: 'Leave',
              icon: const Icon(Icons.logout, size: 20),
              onPressed: () => ref.read(duelSessionProvider.notifier).leave(),
            ),
        ],
      ),
      body: SafeArea(
        child: state.inDuel ? _board(state) : _setup(state),
      ),
    );
  }

  // ---- not in a duel yet ----------------------------------------------------

  Widget _setup(DuelState state) {
    final text = Theme.of(context).textTheme;
    final notifier = ref.read(duelSessionProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      children: [
        Text('A duel nobody has to show up for', style: text.headlineMedium),
        const SizedBox(height: 10),
        Text(
          'Everyone plays a round whenever they like. The longest round today '
          'wins the day. Good for flatmates, colleagues, and anyone you never '
          'manage to eat with.',
          style: text.bodyMedium?.copyWith(color: Colors.white60),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _name,
          maxLength: 30,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name it',
            hintText: 'Flat 3B',
            counterText: '',
          ),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: state.busy ? null : () => notifier.create(_name.text),
          child: Text(state.busy ? 'CREATING…' : 'START A DUEL'),
        ),
        const SizedBox(height: 34),
        Text('Or join one', style: text.titleMedium),
        const SizedBox(height: 10),
        TextField(
          controller: _code,
          textAlign: TextAlign.center,
          maxLength: 4,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: 10,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
            TextInputFormatter.withFunction(
              (_, next) => next.copyWith(text: next.text.toUpperCase()),
            ),
          ],
          decoration: const InputDecoration(counterText: ''),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: state.busy ? null : () => notifier.join(_code.text),
          child: const Text('JOIN'),
        ),
        if (state.error != null) ...[
          const SizedBox(height: 14),
          Text(
            state.error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.danger),
          ),
        ],
      ],
    );
  }

  // ---- in a duel ------------------------------------------------------------

  Widget _board(DuelState state) {
    final board = state.board!;
    final me = state.deviceId;
    final text = Theme.of(context).textTheme;
    final ranked = board.ranked;
    final mine = me == null ? null : board.scoreFor(me);
    final gap = me == null ? null : board.gapFor(me);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      children: [
        _CodeStrip(code: board.duel.code),
        const SizedBox(height: 22),
        _Standing(
          mine: mine,
          gap: gap,
          leading: mine != null && board.leader?.deviceId == me,
          empty: board.nobodyHasPlayed,
        ),
        const SizedBox(height: 26),
        Text('Today', style: text.headlineMedium),
        const SizedBox(height: 10),
        if (ranked.isEmpty)
          Text(
            'Nobody has played yet. Go first.',
            style: text.bodyMedium?.copyWith(color: Colors.white38),
          )
        else
          for (var i = 0; i < ranked.length; i++)
            _Row(
              position: i + 1,
              score: ranked[i],
              isMe: ranked[i].deviceId == me,
              daysWon: board.wins[ranked[i].deviceId] ?? 0,
            ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => context.push(GameScreen.path),
          child: Text(mine == null ? 'PLAY YOUR ROUND' : 'BEAT YOUR TIME'),
        ),
        const SizedBox(height: 10),
        Text(
          'Any solo round counts. Only your longest of the day is kept.',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: Colors.white38, fontSize: 13),
        ),
      ],
    );
  }
}

class _CodeStrip extends StatelessWidget {
  const _CodeStrip({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Duel code copied')),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.1),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            const Text(
              'SHARE THIS CODE',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              code,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: 10,
                color: AppTheme.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where this phone stands — the line someone opens the app to read.
class _Standing extends StatelessWidget {
  const _Standing({
    required this.mine,
    required this.gap,
    required this.leading,
    required this.empty,
  });

  final DuelScore? mine;
  final Duration? gap;
  final bool leading;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final (color, headline, detail) = switch ((mine, leading)) {
      (null, _) when empty => (
          AppTheme.accent,
          'Nobody has played',
          'Set the time to beat.',
        ),
      (null, _) => (
          AppTheme.danger,
          'You have not played today',
          'Everyone else has a time on the board.',
        ),
      (_, true) => (
          AppTheme.safe,
          'You are winning today',
          'Best so far: ${formatClock(mine!.best)}',
        ),
      _ => (
          AppTheme.accent,
          '${formatClock(gap ?? Duration.zero)} behind',
          'Your best today: ${formatClock(mine!.best)}',
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.position,
    required this.score,
    required this.isMe,
    required this.daysWon,
  });

  final int position;
  final DuelScore score;
  final bool isMe;
  final int daysWon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$position',
              style: TextStyle(
                color: position == 1 ? AppTheme.accent : Colors.white38,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              isMe ? '${score.name}  (you)' : score.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isMe ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          if (daysWon > 0) ...[
            Text(
              '$daysWon day${daysWon == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.white24, fontSize: 12),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            formatClock(score.best),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
