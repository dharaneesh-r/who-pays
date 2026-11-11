/// Whether the app asks the phone where it is.
///
/// **Off by default, and that is a policy decision, not an oversight.**
///
/// Turning it on means declaring a location permission, which means a new Play
/// Data Safety declaration. [TODO.md] makes the signing keystore and the
/// hosted privacy policy the two gates before the 14-day / 12-tester closed
/// test, and adding a permission after that clock starts restarts the review.
/// See VENUES.md §7 and §16.
///
/// So until v1 is through that test, the app uses a fixed point and the ballot
/// still works end to end on fake places. To turn it on, both of these are
/// needed — the flag alone does nothing:
///
///   1. Uncomment `ACCESS_COARSE_LOCATION` in
///      `android/app/src/main/AndroidManifest.xml`.
///   2. Build with `--dart-define=LOCATION=true`.
///
/// Coarse only, one fix, never in the background. The search radius is 5 km;
/// nothing here needs to know which table you are sitting at.
abstract final class LocationConfig {
  static const enabled = bool.fromEnvironment('LOCATION');
}
