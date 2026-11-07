import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../paywall/application/purchase_service.dart';
import '../domain/card_pack.dart';

/// Packs shipped with the app, free ones first. Paid packs are bundled too —
/// they are unlocked by purchase, not downloaded.
const _bundledPacks = <String>[
  'assets/cards/friends.json',
  'assets/cards/family.json',
  'assets/cards/couples.json',
  'assets/cards/team.json',
  'assets/cards/deep_talk.json',
  'assets/cards/desi.json',
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

/// Is this pack playable right now?
final packUnlockedProvider = Provider.family<bool, String>((ref, packId) {
  return ref.watch(entitlementsProvider).hasPack(packId);
});

/// The deck currently in play.
///
/// Falls back to a free pack if the selected one is not owned — a lapsed or
/// refunded purchase must never leave the round with no prompts at all.
final promptDeckProvider = Provider<PromptDeck?>((ref) {
  final packs = ref.watch(cardPacksProvider).value;
  if (packs == null || packs.isEmpty) return null;

  final entitlements = ref.watch(entitlementsProvider);
  final playable =
      packs.where((p) => entitlements.hasPack(p.id)).toList();
  if (playable.isEmpty) return null;

  final selectedId = ref.watch(selectedPackProvider);
  final pack = playable.firstWhere(
    (p) => p.id == selectedId,
    orElse: () => playable.first,
  );

  return PromptDeck(pack.prompts);
});
