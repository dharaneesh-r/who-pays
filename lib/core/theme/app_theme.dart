import 'package:flutter/material.dart';

/// The game is read from across a dinner table, often in dim restaurant light.
/// Everything is dark, high contrast and oversized on purpose.
abstract final class AppTheme {
  static const Color bg = Color(0xFF0E0E12);
  static const Color surface = Color(0xFF1A1A21);
  static const Color accent = Color(0xFFFFB300); // timer / brand
  static const Color danger = Color(0xFFE53935); // caught
  static const Color safe = Color(0xFF43A047); // still in the game

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
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          textStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(64),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textTheme: const TextTheme(
        // The running clock. Must be legible from the far side of the table.
        displayLarge: TextStyle(
          fontSize: 88,
          fontWeight: FontWeight.w800,
          letterSpacing: -2,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(fontSize: 16, height: 1.4),
      ),
    );
  }
}
