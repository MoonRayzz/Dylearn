import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color creamBackground    = Color(0xFFFFFBE6);
  static const Color orangePrimary      = Color(0xFFFF9F1C);
  static const Color toscaSecondary     = Color(0xFF2EC4B6);
  static const Color textDark           = Color(0xFF2D3436);
  static const Color orangeLightOpacity = Color(0x4DFF9F1C);
  static const Color grey600            = Color(0xFF757575);

  static const InputDecorationTheme _inputDecorationTheme = InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
      borderSide: BorderSide(color: orangeLightOpacity),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
      borderSide: BorderSide(color: orangeLightOpacity),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
      borderSide: BorderSide(color: orangePrimary, width: 2),
    ),
    labelStyle: TextStyle(color: grey600),
    prefixIconColor: orangePrimary,
  );

  static ThemeData getLightTheme(String? fontFamily) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: creamBackground,
      primaryColor: orangePrimary,
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: orangePrimary,
        onPrimary: Colors.white,
        secondary: toscaSecondary,
        onSecondary: Colors.white,
        error: Colors.red,
        onError: Colors.white,
        surface: creamBackground,
        onSurface: textDark,
      ),
      fontFamily: fontFamily,
      textTheme: TextTheme(
        headlineSmall: GoogleFonts.comicNeue(
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        headlineMedium: GoogleFonts.comicNeue(
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        titleLarge: GoogleFonts.comicNeue(
          fontWeight: FontWeight.bold,
          color: textDark,
        ),
        bodyLarge: const TextStyle(
          color: textDark,
          height: 1.8,
          letterSpacing: 0.5,
          wordSpacing: 2.0,
        ),
        bodyMedium: const TextStyle(
          color: textDark,
          height: 1.6,
          letterSpacing: 0.3,
          wordSpacing: 1.5,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: textDark),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: textDark,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: orangePrimary,
          foregroundColor: Colors.white,
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16))),
          textStyle: TextStyle(
            fontWeight: FontWeight.bold,
            fontFamily: fontFamily,
          ),
        ),
      ),
      inputDecorationTheme: _inputDecorationTheme,
    );
  }

  // FIX: ganti ThemeData.dark() deprecated → ThemeData(brightness: Brightness.dark)
  // FIX: ThemeData.dark() tidak lagi dipanggil 2x — cukup buat satu instance
  // FIX: tambah useMaterial3: true agar konsisten dengan light theme
  static ThemeData getDarkTheme(String? fontFamily) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: orangePrimary,
      colorScheme: const ColorScheme.dark(
        primary: orangePrimary,
        secondary: toscaSecondary,
        surface: Color(0xFF121212),
      ),
      fontFamily: fontFamily,
    );
  }
}