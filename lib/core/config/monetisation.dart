/// How the app makes money right now.
///
/// Launching on ads alone: everything is unlocked for everyone and the Pro
/// purchase is switched off. The purchase code is left in place rather than
/// deleted — turning it back on is a one-line change here, and shipping a
/// paywall before there is any audience only suppresses installs.
enum MonetisationMode {
  /// Free, everything unlocked, interstitial after a round.
  adsOnly,

  /// Ads for free players, one-time Pro unlock removes them.
  adsAndPro,
}

abstract final class Monetisation {
  /// Not `const` so tests can exercise both modes — the Pro paths still have
  /// to work, because this flag is meant to be flipped back on once the app
  /// has an audience.
  static MonetisationMode mode = MonetisationMode.adsOnly;

  static bool get proEnabled => mode == MonetisationMode.adsAndPro;

  /// With Pro off there is nothing to buy, so the store is never queried and
  /// no paywall can appear.
  static bool get purchasesEnabled => proEnabled;
}
