/// Whether the app asks the phone where it is.
///
/// **On as of 11 Nov 2026**, with `ACCESS_COARSE_LOCATION` declared in the
/// manifest. It was off before that, deliberately: declaring the permission
/// means the Play Data Safety form must cover it, and adding one after the
/// 14-day closed test starts restarts review (VENUES.md §7, §16).
///
/// The owner chose to turn it on, because a fixed point meant someone in
/// Coimbatore was shown restaurants in Chennai. **The Data Safety form must
/// now declare approximate location** — that obligation did not go away, it
/// just became due.
///
/// Coarse only, one fix, never in the background. The search radius is 5 km;
/// nothing here needs to know which table you are sitting at.
abstract final class LocationConfig {
  /// On by default as of 11 Nov 2026. The owner tested in Coimbatore and got
  /// restaurants in Chennai, which is what a fixed point always gives you.
  ///
  /// Build with `--dart-define=LOCATION=false` to go back to the fixed point,
  /// which is still useful for a demo with no signal.
  static const enabled = bool.fromEnvironment('LOCATION', defaultValue: true);
}
