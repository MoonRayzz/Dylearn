import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GuruTheme {
  GuruTheme._();

  // Core
  static const Color primary = Color(0xFF00466C);
  static const Color primaryContainer = Color(0xFF1B5E8A);
  static const Color primaryFixed = Color(0xFFCCE5FF);
  static const Color primaryFixedDim = Color(0xFF93CCFE);
  static const Color accentOrange = Color(0xFFE67E22);

  // Surfaces
  static const Color surface = Color(0xFFFAF9F5);
  static const Color surfaceLowest = Color(0xFFFFFFFF);
  static const Color surfaceLow = Color(0xFFF5F4F0);
  static const Color surfaceMid = Color(0xFFEFEEEA);
  static const Color surfaceHigh = Color(0xFFE9E8E4);
  static const Color surfaceHighest = Color(0xFFE3E2DF);

  // Text
  static const Color onSurface = Color(0xFF1B1C1A);
  static const Color onSurfaceVariant = Color(0xFF41474E);
  static const Color outline = Color(0xFF71787F);
  static const Color outlineVariant = Color(0xFFC1C7D0);

  // Semantic
  static const Color successGreen = Color(0xFF2E7D5E);
  static const Color successGreenBg = Color(0xFFE8F5EE);
  static const Color warningAmber = Color(0xFFE69B20);
  static const Color warningAmberBg = Color(0xFFFFF3DC);
  static const Color errorRed = Color(0xFFBA1A1A);
  static const Color errorRedBg = Color(0xFFFFDAD6);

  // Shadow (pre-baked alpha — aman sebagai const)
  static const Color _shadowSm = Color(0x0F1B5E8A);  // ~6%
  static const Color _shadowMd = Color(0x1E1B5E8A);  // ~12%

  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: _shadowSm, blurRadius: 24, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> navShadow = [
    BoxShadow(color: _shadowMd, blurRadius: 32, offset: Offset(0, 8)),
  ];

  static const BoxDecoration cardDecoration = BoxDecoration(
    color: surfaceLowest,
    borderRadius: BorderRadius.all(Radius.circular(16)),
    boxShadow: cardShadow,
  );

  // Avatar palette
  static const List<Color> _avatarColors = [
    Color(0xFF4A90D9),
    Color(0xFF2ECC71),
    Color(0xFF9B59B6),
    Color(0xFFE67E22),
    Color(0xFFE74C3C),
  ];

  static Color avatarColor(String name) =>
      _avatarColors[name.isEmpty ? 0 : name.codeUnitAt(0) % _avatarColors.length];

  static Color scoreColor(double score) {
    if (score >= 80) return successGreen;
    if (score >= 50) return warningAmber;
    return errorRed;
  }

  static Color scoreBg(double score) {
    if (score >= 80) return successGreenBg;
    if (score >= 50) return warningAmberBg;
    return errorRedBg;
  }

  static Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'live':
        return successGreen;
      case 'pending':
      case 'menunggu':
        return warningAmber;
      case 'rejected':
      case 'ditolak':
        return errorRed;
      default:
        return primary;
    }
  }

  static Color statusBg(String status) {
    switch (status.toLowerCase()) {
      case 'live':
        return successGreenBg;
      case 'pending':
      case 'menunggu':
        return warningAmberBg;
      case 'rejected':
      case 'ditolak':
        return errorRedBg;
      default:
        return primaryFixed;
    }
  }

  // Typography — static methods agar bisa terima color dinamis
  static TextStyle display({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: color ?? onSurface,
        height: 1.1,
      );

  static TextStyle headline({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: color ?? onSurface,
      );

  static TextStyle titleLarge({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: color ?? onSurface,
      );

  static TextStyle titleMedium({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: color ?? onSurface,
      );

  static TextStyle bodyMedium({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 13,
        color: color ?? onSurfaceVariant,
      );

  static TextStyle bodySmall({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 11,
        color: color ?? onSurfaceVariant,
      );

  static TextStyle labelMedium({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: color ?? onSurfaceVariant,
      );

  // ALL CAPS section header
  static TextStyle sectionHeader({Color? color}) => GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color ?? outline,
        letterSpacing: 0.8,
      );
}