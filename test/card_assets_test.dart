import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/core/config/monetisation.dart';
import 'package:who_pays/features/cards/domain/card_pack.dart';
import 'package:who_pays/features/paywall/domain/entitlements.dart';

/// The app shipped selling four card packs that did not exist as files. These
/// tests make that impossible to do again: every product on sale must have a
/// pack behind it, and every pack must be real, parseable content.
void main() {
  final dir = Directory('assets/cards');

  List<CardPack> loadAll() {
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .map((f) => CardPack.fromJson(f.readAsStringSync()))
        .toList();
  }

  test('every purchasable pack has a file behind it', () {
    final ids = loadAll().map((p) => p.id).toSet();

    for (final packId in ProductIds.packProducts.keys) {
      expect(ids, contains(packId),
          reason: 'product ${ProductIds.packProducts[packId]} is on sale but '
              'assets/cards/$packId.json does not exist');
    }
  });

  test('every pack file is valid and has enough prompts to last a round', () {
    for (final pack in loadAll()) {
      expect(pack.id, isNotEmpty);
      expect(pack.name, isNotEmpty);
      // A round can run 60 minutes with a prompt every 45 seconds. Fewer than
      // 15 and a long round starts repeating itself.
      expect(pack.prompts.length, greaterThanOrEqualTo(15),
          reason: '${pack.id} has only ${pack.prompts.length} prompts');
      for (final prompt in pack.prompts) {
        expect(prompt.trim(), isNotEmpty);
      }
    }
  });

  test('prompts are unique within a pack', () {
    for (final pack in loadAll()) {
      expect(pack.prompts.toSet().length, pack.prompts.length,
          reason: '${pack.id} repeats a prompt');
    }
  });

  test('exactly the free packs are marked free', () {
    final free = loadAll().where((p) => p.free).map((p) => p.id).toSet();
    expect(free, {'friends', 'family'});
  });

  test('paid packs lock correctly once Pro is switched back on', () {
    Monetisation.mode = MonetisationMode.adsAndPro;
    addTearDown(() => Monetisation.mode = MonetisationMode.adsOnly);

    const nothingOwned = Entitlements.none;
    for (final packId in ProductIds.packProducts.keys) {
      expect(nothingOwned.hasPack(packId), isFalse,
          reason: '$packId must be locked for a free player');
    }

    final pro = Entitlements.none.withPurchase(ProductIds.pro);
    for (final packId in ProductIds.packProducts.keys) {
      expect(pro.hasPack(packId), isTrue);
    }
  });

  test('every pack is free while the app is ads-only', () {
    for (final packId in ProductIds.packProducts.keys) {
      expect(Entitlements.none.hasPack(packId), isTrue);
    }
  });

  test('every pack file is declared in the pubspec asset folder', () {
    // The folder is declared wholesale, so just assert it is still there.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/cards/'));
  });

  test('pack JSON uses the schema the app parses', () {
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(map.keys, containsAll(['id', 'name', 'prompts']));
      expect(map['prompts'], isA<List<dynamic>>());
    }
  });
}
