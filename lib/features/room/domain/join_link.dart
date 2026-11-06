/// Building and reading the link behind the QR code.
///
/// It is an https link rather than a custom scheme on purpose: in phase 10 the
/// same QR has to work for someone who has not installed the app, opening the
/// guest web page instead. One QR, both audiences.
abstract final class JoinLink {
  /// Where the guest page will live. Overridable at build time so the domain
  /// can change without touching code.
  static const host = String.fromEnvironment(
    'JOIN_HOST',
    defaultValue: 'https://who-pays.pages.dev',
  );

  static const _codePattern = r'^[A-HJ-NP-Z]{4}$';

  static String forCode(String code) => '$host/j/${code.toUpperCase()}';

  /// Pulls a table code out of whatever the camera saw.
  ///
  /// Accepts the full link, a custom-scheme link, or a bare code — people
  /// paste all three, and a scanner that only understands one of them feels
  /// broken.
  static String? parse(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;

    final bare = text.toUpperCase();
    if (RegExp(_codePattern).hasMatch(bare)) return bare;

    final uri = Uri.tryParse(text);
    if (uri == null) return null;

    // .../j/ABCD  or  whopays://join/ABCD
    for (final segment in uri.pathSegments.reversed) {
      final candidate = segment.toUpperCase();
      if (RegExp(_codePattern).hasMatch(candidate)) return candidate;
    }

    // ...?code=ABCD
    final query = uri.queryParameters['code']?.toUpperCase();
    if (query != null && RegExp(_codePattern).hasMatch(query)) return query;

    return null;
  }
}
