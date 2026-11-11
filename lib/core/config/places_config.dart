/// Google Places credentials.
///
/// Deliberately **no default**. With no key the app falls back to
/// `FakePlaceProvider`, so a debug build and the test suite never touch the
/// network or spend anything — and a release built without the key degrades to
/// fake places rather than to an error at a dinner table.
///
/// Supply it at build time, the same way the AdMob ids are supplied:
///   flutter build appbundle --dart-define=PLACES_KEY=AIza...
///
/// The key is restricted on Google's side, not here: lock it to the Places API
/// and to this app's package name and signing certificate in the Google Cloud
/// console. A key shipped inside an APK is extractable, so the restriction is
/// the only thing protecting it.
///
/// **Set a hard request quota cap in that console too.** A loop bug without a
/// cap is an unbounded bill. See VENUES.md §14.
abstract final class PlacesConfig {
  static const key = String.fromEnvironment('PLACES_KEY');

  static bool get isConfigured => key.isNotEmpty;
}
