import 'package:flutter/material.dart';

/// The game is read from across a dinner table, often in dim restaurant light.
/// Everything is dark, high contrast and oversized on purpose.
///
/// Both fonts are bundled rather than fetched. Without them the app falls back
/// to each phone's system font — Realme, Samsung and Pixel all ship different
/// ones, so the app looked like a different product on every device.
abstract final class AppTheme {
  static const bg = Color(0xFF0E0E12);
  static const surface = Color(0xFF17171E);
  static const surfaceHigh = Color(0xFF212129);
  static const accent = Color(0xFFFFB300); // timer / brand
  static const danger = Color(0xFFE5392F); // caught
  static const safe = Color(0xFF3DD68C); // still in the game

  /// Headlines only. Anton is heavy and condensed — it shouts, which is the
  /// right register for a game about public embarrassment.
  static const display = 'Anton';

  /// Everything else. Inter is a variable font, so weights are applied through
  /// [FontVariation] rather than `fontWeight`, which a variable font ignores.
  static const body = 'Inter';

  static List<FontVariation> weight(double w) => [FontVariation('wght', w)];

  /// The clock. Tabular figures stop the digits jittering as they tick.
  static const _tabular = [FontFeature.tabularFigures()];

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: body,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          fontFamily: display,
          fontSize: 22,
          letterSpacing: 1,
          color: Colors.white,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(62),
          textStyle: const TextStyle(
            fontFamily: display,
            fontSize: 20,
            letterSpacing: 1.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(62),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
          textStyle: const TextStyle(
            fontFamily: display,
            fontSize: 18,
            letterSpacing: 1.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: accent.withValues(alpha: 0.22),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        labelStyle: TextStyle(
          fontFamily: body,
          fontSize: 13.5,
          fontVariations: weight(600),
          color: Colors.white.withValues(alpha: 0.92),
        ),
        // Tight enough that two stake chips fit on one row at 360dp. Any
        // roomier and every chip claims a line of its own, which pushed the
        // pack picker off the screen.
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(fontFamily: body, color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      textTheme: TextTheme(
        // The running clock. Must be legible from the far side of the table.
        displayLarge: const TextStyle(
          fontFamily: body,
          fontSize: 88,
          height: 1,
          letterSpacing: -3,
          fontVariations: [FontVariation('wght', 800)],
          fontFeatures: _tabular,
        ),
        // Big shouty headlines: WHO PAYS?, CAUGHT, DON'T TOUCH IT.
        displayMedium: const TextStyle(
          fontFamily: display,
          fontSize: 64,
          height: 1.02,
          letterSpacing: 0.5,
        ),
        headlineMedium: const TextStyle(
          fontFamily: display,
          fontSize: 26,
          letterSpacing: 0.6,
        ),
        titleMedium: TextStyle(
          fontFamily: body,
          fontSize: 17,
          fontVariations: weight(650),
        ),
        bodyMedium: TextStyle(
          fontFamily: body,
          fontSize: 15,
          height: 1.45,
          fontVariations: weight(450),
        ),
        labelLarge: TextStyle(
          fontFamily: body,
          fontSize: 14,
          fontVariations: weight(600),
        ),
      ),
    );
  }
}
