/// Supabase connection details.
///
/// The publishable (anon) key is designed to ship inside a client app — it only
/// grants what row-level security allows. The `service_role` key must never
/// appear here or anywhere else in this project.
///
/// Both can be overridden at build time without editing this file:
///   flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
abstract final class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://uhslpvssmpmhtmlmncxo.supabase.co',
  );

  static const publishableKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_3oYIMsneJAbIFvDUP7N_Bw_xqxo-UIn',
  );

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}
