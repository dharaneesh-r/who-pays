import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/card_pack.dart';

/// Packs shipped with the app. Paid packs get added here and gated on the
/// purchase in phase 11.
const _bundledPacks = <String>[
  'assets/cards/friends.json',
  'assets/cards/family.json',
];

final cardPacksProvider = FutureProvider<List<CardPack>>((ref) async {
  final packs = <CardPack>[];
  for (final path in _bundledPacks) {
    try {
      packs.add(CardPack.fromJson(await rootBundle.loadString(path)));
    } catch (_) {
      // A malformed pack must not take the app down — just skip it.
    }
  }
  return packs;
});

/// Which pack the table is using. Defaults to the first free one.
class SelectedPack extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedPackProvider =
    NotifierProvider<SelectedPack, String?>(SelectedPack.new);

/// The deck currently in play, reshuffled whenever the pack changes.
final promptDeckProvider = Provider<PromptDeck?>((ref) {
  final packs = ref.watch(cardPacksProvider).value;
  if (packs == null || packs.isEmpty) return null;

  final selectedId = ref.watch(selectedPackProvider);
  final pack = packs.firstWhere(
    (p) => p.id == selectedId,
    orElse: () => packs.first,
  );

  return PromptDeck(pack.prompts);
});
