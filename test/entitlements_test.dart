import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/features/paywall/domain/entitlements.dart';

void main() {
  group('a free player', () {
    const free = Entitlements.none;

    test('is not pro and still sees ads', () {
      expect(free.isPro, isFalse);
      expect(free.adsRemoved, isFalse);
    });

    test('gets the free rounds, then is asked to pay', () {
      expect(free.canPlay(roundsToday: 0), isTrue);
      expect(free.canPlay(roundsToday: 2), isTrue);
      expect(free.canPlay(roundsToday: 3), isFalse);
      expect(free.canPlay(roundsToday: 99), isFalse);
    });

    test('reports how many rounds are left, never a negative', () {
      expect(free.roundsLeft(roundsToday: 0), 3);
      expect(free.roundsLeft(roundsToday: 2), 1);
      expect(free.roundsLeft(roundsToday: 3), 0);
      expect(free.roundsLeft(roundsToday: 10), 0);
    });

    test('has the free packs but not the paid ones', () {
      expect(free.hasPack('friends'), isTrue,
          reason: 'a pack with no product attached is free');
      expect(free.hasPack('family'), isTrue);
      expect(free.hasPack('couples'), isFalse);
      expect(free.hasPack('desi'), isFalse);
    });
  });

  group('a pro player', () {
    final pro = Entitlements.none.withPurchase(ProductIds.pro);

    test('has unlimited rounds', () {
      expect(pro.canPlay(roundsToday: 1000), isTrue);
      expect(pro.roundsLeft(roundsToday: 1000), -1);
    });

    test('has no ads', () => expect(pro.adsRemoved, isTrue));

    test('gets every pack without buying them individually', () {
      for (final packId in ProductIds.packProducts.keys) {
        expect(pro.hasPack(packId), isTrue, reason: 'pro must include $packId');
      }
    });
  });

  group('buying a single pack', () {
    final buyer = Entitlements.none.withPurchase(ProductIds.packCouples);

    test('unlocks only that pack', () {
      expect(buyer.hasPack('couples'), isTrue);
      expect(buyer.hasPack('team'), isFalse);
    });

    test('does not make them pro', () {
      expect(buyer.isPro, isFalse);
      expect(buyer.adsRemoved, isFalse);
      expect(buyer.canPlay(roundsToday: 3), isFalse);
    });
  });

  group('purchase bookkeeping', () {
    test('ignores an unknown product id', () {
      final result = Entitlements.none.withPurchase('not_a_real_product');
      expect(result.owned, isEmpty);
    });

    test('buying twice does not duplicate', () {
      final twice = Entitlements.none
          .withPurchase(ProductIds.pro)
          .withPurchase(ProductIds.pro);
      expect(twice.owned.length, 1);
    });

    test('a refund revokes the entitlement', () {
      final refunded = Entitlements.none
          .withPurchase(ProductIds.pro)
          .withRevocation(ProductIds.pro);
      expect(refunded.isPro, isFalse);
      expect(refunded.hasPack('couples'), isFalse);
    });

    test('revoking something never owned is harmless', () {
      expect(
        Entitlements.none.withRevocation(ProductIds.pro).owned,
        isEmpty,
      );
    });
  });
}
