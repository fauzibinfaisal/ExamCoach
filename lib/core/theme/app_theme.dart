import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _navy = Color(0xFF17324D);
  static const _teal = Color(0xFF147D78);
  static const _background = Color(0xFFF4F7F9);

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _teal,
      brightness: Brightness.light,
      primary: _navy,
      secondary: _teal,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _background,
      appBarTheme: const AppBarTheme(
        backgroundColor: _background,
        foregroundColor: _navy,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE1E8ED)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: _navy,
          fontSize: 34,
          height: 1.12,
          fontWeight: FontWeight.w800,
        ),
        headlineMedium: TextStyle(
          color: _navy,
          fontSize: 26,
          height: 1.2,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: TextStyle(
          color: _navy,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.5,
          color: Color(0xFF34495E),
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: Color(0xFF526675),
        ),
      ),
    );
  }
}
