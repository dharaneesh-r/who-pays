import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/core/config/monetisation.dart';
import 'package:who_pays/features/paywall/domain/entitlements.dart';

void main() {
  tearDown(() => Monetisation.mode = MonetisationMode.adsOnly);

  group('ads-only launch (how the app ships today)', () {
    setUp(() => Monetisation.mode = MonetisationMode.adsOnly);

    const player = Entitlements.none;

    test('rounds are unlimited — there is no paywall to hit', () {
      expect(player.canPlay(roundsToday: 0), isTrue);
      expect(player.canPlay(roundsToday: 500), isTrue);
      expect(player.roundsLeft(roundsToday: 500), -1);
    });

    test('every pack is unlocked', () {
      for (final packId in ProductIds.packProducts.keys) {
        expect(player.hasPack(packId), isTrue, reason: '$packId must be free');
      }
      expect(player.hasPack('friends'), isTrue);
    });

    test('custom stakes are available to everyone', () {
      expect(player.canUseCustomStake, isTrue);
    });

    test('ads are always shown — they are the only revenue', () {
      expect(player.adsRemoved, isFalse);
      // Even a leftover Pro entitlement from a previous build cannot remove
      // ads while the app is in ads-only mode.
      final legacyPro = Entitlements.none.withPurchase(ProductIds.pro);
      expect(legacyPro.adsRemoved, isFalse);
    });
  });

  group('with Pro switched back on', () {
    setUp(() => Monetisation.mode = MonetisationMode.adsAndPro);

    test('a free player gets the daily allowance, then is asked to pay', () {
      const free = Entitlements.none;
      expect(free.canPlay(roundsToday: 0), isTrue);
      expect(free.canPlay(roundsToday: 2), isTrue);
      expect(free.canPlay(roundsToday: 3), isFalse);
      expect(free.roundsLeft(roundsToday: 2), 1);
      expect(free.roundsLeft(roundsToday: 10), 0);
    });

    test('a free player has the free packs but not the paid ones', () {
      const free = Entitlements.none;
      expect(free.hasPack('friends'), isTrue);
      expect(free.hasPack('couples'), isFalse);
      expect(free.canUseCustomStake, isFalse);
    });

    test('pro unlocks everything and removes ads', () {
      final pro = Entitlements.none.withPurchase(ProductIds.pro);
      expect(pro.canPlay(roundsToday: 1000), isTrue);
      expect(pro.adsRemoved, isTrue);
      expect(pro.canUseCustomStake, isTrue);
      for (final packId in ProductIds.packProducts.keys) {
        expect(pro.hasPack(packId), isTrue);
      }
    });

    test('buying one pack unlocks only that pack', () {
      final buyer = Entitlements.none.withPurchase(ProductIds.packCouples);
      expect(buyer.hasPack('couples'), isTrue);
      expect(buyer.hasPack('team'), isFalse);
      expect(buyer.isPro, isFalse);
      expect(buyer.adsRemoved, isFalse);
    });
  });

  group('purchase bookkeeping', () {
    test('ignores an unknown product id', () {
      expect(Entitlements.none.withPurchase('not_real').owned, isEmpty);
    });

    test('buying twice does not duplicate', () {
      final twice = Entitlements.none
          .withPurchase(ProductIds.pro)
          .withPurchase(ProductIds.pro);
      expect(twice.owned.length, 1);
    });

    test('a refund revokes the entitlement', () {
      Monetisation.mode = MonetisationMode.adsAndPro;
      final refunded = Entitlements.none
          .withPurchase(ProductIds.pro)
          .withRevocation(ProductIds.pro);
      expect(refunded.isPro, isFalse);
      expect(refunded.hasPack('couples'), isFalse);
    });

    test('revoking something never owned is harmless', () {
      expect(Entitlements.none.withRevocation(ProductIds.pro).owned, isEmpty);
    });
  });
}
