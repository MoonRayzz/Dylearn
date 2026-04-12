// lib/utils/responsive_helper.dart

import 'package:flutter/material.dart';

/// Breakpoint standard:
/// - Phone   : < 600px
/// - Tablet  : 600px – 899px
/// - Large   : ≥ 900px
class ResponsiveHelper {
  final BuildContext context;
  final double width;
  final double height;

  ResponsiveHelper(this.context)
      : width = MediaQuery.of(context).size.width,
        height = MediaQuery.of(context).size.height;

  // ── Breakpoint checks ──────────────────────────
  bool get isPhone => width < 600;
  bool get isTablet => width >= 600 && width < 900;
  bool get isLargeTablet => width >= 900;
  bool get isTabletOrLarger => width >= 600;

  // ── Font scaling ───────────────────────────────
  /// [phone] ukuran default hp, [tablet] opsional override
  double font(double phone, {double? tablet, double? large}) {
    if (isLargeTablet) return large ?? tablet ?? phone * 1.35;
    if (isTablet) return tablet ?? phone * 1.2;
    return phone;
  }

  // ── Spacing / padding scaling ──────────────────
  double spacing(double phone, {double? tablet, double? large}) {
    if (isLargeTablet) return large ?? tablet ?? phone * 1.4;
    if (isTablet) return tablet ?? phone * 1.25;
    return phone;
  }

  // ── Widget size scaling ────────────────────────
  double size(double phone, {double? tablet, double? large}) {
    if (isLargeTablet) return large ?? tablet ?? phone * 1.3;
    if (isTablet) return tablet ?? phone * 1.15;
    return phone;
  }

  // ── Content max width (centering di layar lebar) ─
  /// Membatasi lebar konten agar tidak melar di tablet/desktop
  double get contentMaxWidth {
    if (isLargeTablet) return 700;
    if (isTablet) return 560;
    return double.infinity;
  }

  /// Padding horizontal adaptif
  double get horizontalPadding {
    if (isLargeTablet) return width * 0.12;
    if (isTablet) return width * 0.08;
    return 24.0;
  }

  /// Kolom grid untuk layout 2-column di tablet
  int get gridColumns => isTabletOrLarger ? 2 : 1;

  // ── Convenience: value picker ──────────────────
  T pick<T>(T phone, {required T tablet, T? large}) {
    if (isLargeTablet) return large ?? tablet;
    if (isTablet) return tablet;
    return phone;
  }
}

/// Extension agar bisa dipakai langsung dari context
extension ResponsiveContext on BuildContext {
  ResponsiveHelper get r => ResponsiveHelper(this);
}