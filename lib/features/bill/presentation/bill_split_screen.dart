import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/local/prefs_service.dart';
import '../../game/application/game_controller.dart';
import '../../game/domain/game_models.dart';
import '../../room/application/room_session.dart';
import '../domain/bill_split.dart';
import '../domain/money.dart';
import '../domain/participant_seed.dart';

/// Who owes what.
///
/// Spec: VENUES.md §15. The screen is **stake-aware**: it reads the bet the
/// table actually played for. If the stake was the bill, the loser owes all of
/// it and everyone else owes nothing. If the stake was anything else — next
/// round, dishes, chores — the bill is divided and the stake is settled off
/// the app. Without that, the app would announce "Bala pays the bill" on one
/// screen and ask everyone for a quarter of it on the next.
class BillSplitScreen extends ConsumerStatefulWidget {
  const BillSplitScreen({super.key});

  static const path = '/split';

  @override
  ConsumerState<BillSplitScreen> createState() => _BillSplitScreenState();
}

class _BillSplitScreenState extends ConsumerState<BillSplitScreen> {
  final _amount = TextEditingController();
  final _newName = TextEditingController();

  /// Tip offered as whole percentages. Zero first, because tipping is not
  /// customary everywhere this ships and the default must not nudge.
  static const _tipOptions = [0, 5, 10, 15];
  int _tipPercent = 0;

  /// Everyone in the split, in order. Seeded from the table, editable —
  /// somebody always turns up late or leaves before the bill.
  List<String> _people = [];

  /// Names unticked because they did not eat.
  final Set<String> _excluded = {};

  bool _seeded = false;

  /// Whether the seed came from the room's own player list rather than from
  /// the solo fallback of just this phone's name.
  bool _seededFromTable = false;

  /// Set the moment the user adds or unticks anybody. After that the list is
  /// theirs, and a late room update must never overwrite it.
  bool _edited = false;

  @override
  void dispose() {
    _amount.dispose();
    _newName.dispose();
    super.dispose();
  }

  /// Seed the list once, from the room if there is one, otherwise from the
  /// saved player name. Done here rather than in initState because the room
  /// snapshot and the stored name both arrive asynchronously.
  /// The rule itself lives in [seedParticipants], which is a pure function
  /// with its own tests — it is fiddly, and getting it wrong once meant five
  /// people at a table being told they owed nothing.
  void _seed(List<String> names, {required bool fromTable}) {
    final seeded = seedParticipants(
      candidate: names,
      fromTable: fromTable,
      alreadySeeded: _seeded,
      alreadySeededFromTable: _seededFromTable,
      edited: _edited,
    );
    if (seeded == null) return;

    _seeded = true;
    _seededFromTable = fromTable;
    _people = seeded;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final game = ref.watch(gameControllerProvider);
    final room = ref.watch(roomSessionProvider);
    final myName = ref.watch(playerNameProvider).value;

    // The loser is whoever cracked *first*, which only the room knows. Solo
    // rounds have no loser worth naming — "You" owing yourself money is not
    // a split.
    final loser = room.snapshot?.loser?.name;

    final tableNames = room.snapshot?.standings.map((p) => p.name).toList();
    if (tableNames != null && tableNames.isNotEmpty) {
      _seed(tableNames, fromTable: true);
    } else if (myName != null) {
      _seed([myName], fromTable: false);
    }

    final participants =
        _people.where((n) => !_excluded.contains(n)).toList();

    final split = BillSplit.compute(
      amountMinor: parseMinor(_amount.text) ?? 0,
      stake: game.config.stake,
      participants: participants,
      loser: loser,
      tipPercent: _tipPercent,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('SPLIT THE BILL')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _StakeNote(
              stake: game.config.stake,
              stakeText: game.config.stakeText,
              loser: loser,
              loserPaysEverything: split.loserPaysEverything,
            ),
            const SizedBox(height: 18),
            Text('WHAT WAS THE BILL?', style: text.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // Forgiving on purpose: people type "₹2,400" and "2400.50".
              // parseMinor strips the rest.
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,₹$ ]')),
              ],
              style: const TextStyle(
                fontFamily: AppTheme.body,
                fontSize: 30,
                fontVariations: [FontVariation('wght', 700)],
              ),
              decoration: const InputDecoration(hintText: '0'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Text('TIP', style: text.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final pct in _tipOptions)
                  ChoiceChip(
                    label: Text(pct == 0 ? 'None' : '$pct%'),
                    selected: _tipPercent == pct,
                    onSelected: (_) => setState(() => _tipPercent = pct),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('WHO IS IN', style: text.labelLarge),
            const SizedBox(height: 4),
            Text(
              'Untick anyone who did not eat.',
              style: text.bodyMedium
                  ?.copyWith(color: Colors.white38, fontSize: 12.5),
            ),
            const SizedBox(height: 6),
            for (final name in _people)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: !_excluded.contains(name),
                title: Text(
                  name + (name == loser ? '  · cracked first' : ''),
                  style: TextStyle(
                    color: name == loser ? AppTheme.danger : null,
                  ),
                ),
                onChanged: (on) => setState(() {
                  _edited = true;
                  if (on == true) {
                    _excluded.remove(name);
                  } else {
                    _excluded.add(name);
                  }
                }),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'Add someone',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addPerson(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _addPerson,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _Totals(split: split),
            const SizedBox(height: 10),
            if (split.shares.isEmpty)
              Text(
                'Nobody is in the split yet.',
                style: text.bodyMedium?.copyWith(color: Colors.white38),
              )
            else
              for (final share in split.shares)
                _ShareRow(
                  share: share,
                  highlight: split.loserPaysEverything && share.isLoser,
                ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: split.totalMinor == 0 || split.shares.isEmpty
                  ? null
                  : () => _share(split, game.config),
              icon: const Icon(Icons.ios_share),
              label: const Text('SEND IT TO THE GROUP'),
            ),
          ],
        ),
      ),
    );
  }

  void _addPerson() {
    final name = _newName.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _edited = true;
      // Duplicate names are allowed at a real table — two Devs happen — but
      // adding the same string twice by accident is just a mis-tap.
      if (!_people.contains(name)) _people = [..._people, name];
      _newName.clear();
    });
  }

  /// Plain text rather than an image: this gets pasted into a WhatsApp group
  /// where people need to read the number, not admire a card.
  Future<void> _share(BillSplit split, GameConfig config) async {
    final lines = [
      if (split.loserPaysEverything)
        'Who Pays? — the bill is on the loser.'
      else
        'Who Pays? — splitting the bill.',
      '',
      'Total: ${formatMoney(split.totalMinor)}'
          '${split.tipMinor > 0 ? ' (incl. ${formatMoney(split.tipMinor)} tip)' : ''}',
      '',
      for (final s in split.shares)
        '${s.name}: ${formatMoney(s.amountMinor)}'
            '${s.isLoser ? '  ← ${config.stakeText}' : ''}',
    ];

    await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }
}

/// Says, in one sentence, which of the two answers this screen is giving and
/// why — so nobody has to work out why three people owe nothing.
class _StakeNote extends StatelessWidget {
  const _StakeNote({
    required this.stake,
    required this.stakeText,
    required this.loser,
    required this.loserPaysEverything,
  });

  final Stake stake;
  final String stakeText;
  final String? loser;
  final bool loserPaysEverything;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = loserPaysEverything ? AppTheme.danger : AppTheme.accent;

    final message = loserPaysEverything
        ? '$loser cracked first and the stake was the bill, so the whole '
            'thing is on them.'
        : stake == Stake.bill
            ? 'Nobody cracked, so there is no one to charge — the bill '
                'splits evenly.'
            : 'The stake was “$stakeText”, not the bill, so this splits '
                'evenly. Settle the stake yourselves.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(message, style: text.bodyMedium),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.split});

  final BillSplit split;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _row(context, 'Bill', split.subtotalMinor),
        if (split.tipMinor > 0) _row(context, 'Tip', split.tipMinor),
        const Divider(height: 18),
        _row(context, 'Total', split.totalMinor, bold: true),
      ],
    );
  }

  Widget _row(BuildContext context, String label, int minor,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: bold ? Colors.white : Colors.white54,
              fontSize: bold ? 16 : 14,
            ),
          ),
          Text(
            formatMoney(minor),
            style: TextStyle(
              fontFamily: AppTheme.body,
              fontSize: bold ? 20 : 15,
              fontVariations: AppTheme.weight(bold ? 750 : 550),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.share, required this.highlight});

  final BillShare share;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: highlight
            ? AppTheme.danger.withValues(alpha: 0.14)
            : AppTheme.surface,
        border: Border.all(
          color: highlight
              ? AppTheme.danger.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.08),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              share.name,
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formatMoney(share.amountMinor),
            style: TextStyle(
              fontFamily: AppTheme.body,
              fontSize: 19,
              fontVariations: AppTheme.weight(750),
              fontFeatures: const [FontFeature.tabularFigures()],
              color: share.amountMinor == 0 ? Colors.white38 : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
