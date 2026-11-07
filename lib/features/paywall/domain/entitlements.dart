import '../../../core/config/monetisation.dart';

/// What the player has paid for.
///
/// Deliberately one-time purchases, never a subscription: nobody subscribes to
/// a game they play four times a month, and trying makes the paywall feel
/// predatory in exactly the market this app launches in.
abstract final class ProductIds {
  /// Removes ads, unlocks custom stakes, full stats and every pack.
  static const pro = 'who_pays_pro';

  /// Individual conversation packs for people who will not buy Pro.
  static const packCouples = 'pack_couples';
  static const packTeam = 'pack_team';
  static const packDeepTalk = 'pack_deep_talk';
  static const packDesi = 'pack_desi';

  static const all = <String>{
    pro,
    packCouples,
    packTeam,
    packDeepTalk,
    packDesi,
  };

  /// Maps a card pack id to the product that unlocks it.
  static const packProducts = <String, String>{
    'couples': packCouples,
    'team': packTeam,
    'deep_talk': packDeepTalk,
    'desi': packDesi,
  };
}

class Entitlements {
  const Entitlements({this.owned = const {}});

  static const none = Entitlements();

  final Set<String> owned;

  bool get isPro => owned.contains(ProductIds.pro);

  /// Pro includes every pack, so pack ownership is never checked separately
  /// for a Pro user — a bug there would be an immediate refund request.
  bool hasPack(String packId) {
    // Ads-only launch: every pack is free.
    if (!Monetisation.proEnabled) return true;
    if (isPro) return true;
    final product = ProductIds.packProducts[packId];
    return product == null || owned.contains(product);
  }

  /// Custom stakes are a Pro feature only while Pro exists.
  bool get canUseCustomStake => !Monetisation.proEnabled || isPro;

  /// On an ads-only launch nobody can remove the ads — they are the revenue.
  bool get adsRemoved => Monetisation.proEnabled && isPro;

  /// Free players get a few rounds a day. Enough to fall in love with it,
  /// few enough that a group playing every week has a reason to buy.
  static const freeRoundsPerDay = 3;

  bool canPlay({required int roundsToday}) =>
      !Monetisation.proEnabled || isPro || roundsToday < freeRoundsPerDay;

  /// -1 means unlimited.
  int roundsLeft({required int roundsToday}) =>
      (!Monetisation.proEnabled || isPro)
          ? -1
          : (freeRoundsPerDay - roundsToday).clamp(0, freeRoundsPerDay);

  Entitlements withPurchase(String productId) {
    if (!ProductIds.all.contains(productId)) return this;
    return Entitlements(owned: {...owned, productId});
  }

  Entitlements withRevocation(String productId) =>
      Entitlements(owned: {...owned}..remove(productId));
}
