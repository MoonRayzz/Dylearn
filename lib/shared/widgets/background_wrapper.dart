// ignore_for_file: deprecated_member_use, unused_element_parameter

import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../core/utils/responsive_helper.dart';

// ════════════════════════════════════════════════════════════════
// TOP-LEVEL KONSTANTA
// Dihitung sekali saat file dimuat, bukan setiap frame animasi.
// ════════════════════════════════════════════════════════════════

/// FIX PERFORMANCE: Cache 2π sebagai konstanta top-level.
/// Sebelumnya `2 * math.pi` dihitung ulang setiap frame (~60x/detik)
/// di dalam builder _FloatingIcon yang isWobbling.
const double _twoPi = 2 * math.pi;

class BackgroundWrapper extends StatefulWidget {
  final Widget child;
  final bool showBottomBlob;
  final bool enableFloatingShapes;

  const BackgroundWrapper({
    super.key,
    required this.child,
    this.showBottomBlob = true,
    this.enableFloatingShapes = true,
  });

  @override
  State<BackgroundWrapper> createState() => _BackgroundWrapperState();
}

class _BackgroundWrapperState extends State<BackgroundWrapper>
    with TickerProviderStateMixin {
  late final AnimationController _floatController;
  late final AnimationController _rotateController;

  @override
  void initState() {
    super.initState();

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );

    // FIX BUG: Hanya jalankan _rotateController jika benar-benar dibutuhkan.
    // Sebelumnya controller selalu repeat() meski enableFloatingShapes = false,
    // membuang CPU untuk animasi yang tidak pernah ditampilkan.
    if (widget.enableFloatingShapes) {
      _rotateController.repeat();
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FIX PERFORMANCE: Cache ThemeData sekali per build.
    // Sebelumnya Theme.of(context) dipanggil 2x — sekali untuk colorScheme,
    // sekali lagi inline untuk scaffoldBackgroundColor.
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // RESPONSIVENESS: Ambil helper sekali, teruskan ke sub-widget sebagai
    // parameter ukuran agar sub-widget tetap StatelessWidget murni
    // tanpa perlu akses context sendiri.
    final r = context.r;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── LAYER 1: BACKGROUND (DIISOLASI) ─────────────────────
        // RepaintBoundary krusial: animasi background tidak memaksa
        // widget child (konten utama) untuk repaint setiap frame.
        RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Warna dasar layar
              ColoredBox(
                // FIX: Gunakan ColoredBox — lebih ringan dari Container
                // karena tidak membuat BoxDecoration + hanya painting solid color.
                color: theme.scaffoldBackgroundColor,
              ),

              // Blob Atas Kiri
              _AnimatedBlob(
                animation: _floatController,
                // RESPONSIVE: Ukuran blob adaptif
                top: r.size(-50),
                left: r.size(-50),
                size: r.size(200),
                color: colorScheme.secondary.withOpacity(0.1),
              ),

              // Blob Tengah Kanan
              if (widget.showBottomBlob)
                _AnimatedBlob(
                  animation: _floatController,
                  // RESPONSIVE: Posisi & ukuran adaptif
                  top: r.size(150),
                  right: r.size(-80),
                  size: r.size(180),
                  color: colorScheme.primary.withOpacity(0.1),
                  reverse: true,
                ),

              // Bentuk Melayang — hanya render jika flag aktif
              if (widget.enableFloatingShapes) ...[
                _FloatingIcon(
                  animation: _rotateController,
                  // RESPONSIVE: Posisi ikon adaptif
                  top: r.size(100),
                  right: r.size(40),
                  icon: Icons.star,
                  // Konstanta warna — tidak perlu withOpacity() runtime
                  color: const Color(0x4DFFEB3B),
                  isRotating: true,
                  // RESPONSIVE: Ukuran ikon adaptif
                  iconSize: r.size(28),
                ),
                _FloatingIcon(
                  animation: _floatController,
                  top: r.size(200),
                  left: r.size(30),
                  icon: Icons.favorite,
                  color: const Color(0x33E91E63),
                  iconSize: r.size(28),
                ),
                _FloatingIcon(
                  animation: _rotateController,
                  bottom: r.size(150),
                  right: r.size(50),
                  icon: Icons.emoji_emotions,
                  color: const Color(0x40FF9800),
                  isWobbling: true,
                  floatAnimation: _floatController,
                  iconSize: r.size(28),
                ),
              ],
            ],
          ),
        ),

        // ── LAYER 2: KONTEN UTAMA ────────────────────────────────
        // SafeArea di sini karena BackgroundWrapper membungkus
        // seluruh halaman termasuk area unsafe (notch, status bar).
        SafeArea(child: widget.child),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _AnimatedBlob
//
// Blob lingkaran yang bergerak naik-turun menggunakan Transform.translate
// murni di GPU — tidak menyebabkan layout pass setiap frame.
// ════════════════════════════════════════════════════════════════

class _AnimatedBlob extends StatelessWidget {
  final Animation<double> animation;
  final double? top, left, right, bottom;
  final double size;
  final Color color;
  final bool reverse;

  const _AnimatedBlob({
    required this.animation,
    required this.size,
    required this.color,
    this.top,
    this.left,
    this.right,
    this.bottom,
    this.reverse = false,
  });

  @override
  Widget build(BuildContext context) {
    // OPTIMASI: Positioned dibuat STATIS di luar AnimatedBuilder.
    // Mencegah Flutter melakukan layout pass setiap frame animasi.
    // Hanya Transform (GPU operation) yang berubah setiap frame.
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: AnimatedBuilder(
        animation: animation,
        // child statis: tidak di-instansiasi ulang setiap frame
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        builder: (context, staticChild) {
          final val = reverse ? (1.0 - animation.value) : animation.value;
          // Transform murni via GPU — tidak trigger layout atau paint pass baru
          return Transform.translate(
            offset: Offset(0, val * 15),
            child: staticChild!,
          );
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// _FloatingIcon
//
// FIX: Pindahkan Listenable.merge ke field instance.
//
// BUG SEBELUMNYA:
//   Listenable.merge([animation, floatAnimation]) dibuat di dalam build(),
//   artinya objek Listenable baru dibuat setiap kali build() dipanggil.
//   AnimatedBuilder mendeteksi perubahan listenable → unsubscribe lama
//   → re-subscribe baru → overhead tidak perlu setiap rebuild.
//
// FIX:
//   Buat _effectiveListenable sebagai field yang dihitung sekali
//   saat widget dibuat. AnimatedBuilder hanya subscribe satu kali.
// ════════════════════════════════════════════════════════════════

class _FloatingIcon extends StatelessWidget {
  final Animation<double> animation;
  final Animation<double>? floatAnimation;
  final double? top, left, right, bottom;
  final IconData icon;
  final Color color;
  final bool isRotating;
  final bool isWobbling;
  final double iconSize;

  // FIX: Listenable dihitung sekali sebagai field — bukan di build()
  late final Listenable _effectiveListenable;

  _FloatingIcon({
    required this.animation,
    required this.icon,
    required this.color,
    required this.iconSize,
    this.floatAnimation,
    this.top,
    this.left,
    this.right,
    this.bottom,
    this.isRotating = false,
    this.isWobbling = false,
  }) {
    // Merge hanya jika floatAnimation tersedia — objek dibuat sekali saja
    _effectiveListenable = floatAnimation != null
        ? Listenable.merge([animation, floatAnimation!])
        : animation;
  }

  @override
  Widget build(BuildContext context) {
    // RESPONSIVENESS: iconSize sudah diteruskan dari parent sebagai r.size(28)
    final staticIcon = Icon(icon, color: color, size: iconSize);

    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: AnimatedBuilder(
        // FIX: Gunakan field _effectiveListenable — tidak buat objek baru tiap build
        animation: _effectiveListenable,
        child: staticIcon,
        builder: (context, child) {
          Widget current = child!;

          if (isRotating) {
            current = Transform.rotate(
              // FIX PERFORMANCE: Gunakan konstanta _twoPi
              // bukan `2 * math.pi` yang dihitung ulang 60x/detik
              angle: animation.value * _twoPi,
              child: current,
            );
          } else if (isWobbling) {
            current = Transform.rotate(
              // FIX PERFORMANCE: Gunakan _twoPi — nilai konstan
              angle: math.sin(animation.value * _twoPi) * 0.2,
              child: Transform.translate(
                offset: Offset((floatAnimation?.value ?? 0) * 5, 0),
                child: current,
              ),
            );
          } else {
            current = Transform.translate(
              offset: Offset(0, animation.value * 10),
              child: current,
            );
          }

          return current;
        },
      ),
    );
  }
}