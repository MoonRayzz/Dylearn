// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart'; // DITAMBAHKAN untuk animasi

import 'auth/login_screen.dart';
import 'auth/register_screen.dart';
import '../shared/widgets/background_wrapper.dart';
import '../core/services/auth_service.dart';
import '../core/utils/responsive_helper.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late VideoPlayerController _controller;

  final ValueNotifier<bool> _isVideoInitialized = ValueNotifier(false);
  final ValueNotifier<bool> _isGoogleLoadingNotifier = ValueNotifier(false);

  bool _isDisposed = false;
  double _cachedAspectRatio = 16 / 9;

  // BUG FIX #3: Cache AuthService sebagai field
  // Mencegah object baru dibuat setiap kali tombol ditekan
  final AuthService _authService = AuthService();

  // OPTIMIZATION: Cache warna withOpacity → static final
  static final Color _videoShadowColor = Colors.orange.withOpacity(0.2);
  static final Color _containerShadowColor = Colors.orange.withOpacity(0.15);

  // OPTIMIZATION: Cache BoxDecoration video → static final
  // Nilai konstan, tidak perlu dibuat ulang setiap build()
  static final BoxDecoration _videoContainerDecoration = BoxDecoration(
    borderRadius: BorderRadius.circular(30),
    boxShadow: [
      BoxShadow(
        color: _videoShadowColor,
        blurRadius: 15,
        offset: const Offset(0, 8),
      )
    ],
  );

  // OPTIMIZATION: Cache BorderRadius konstan → static const
  static const BorderRadius _videoClipRadius =
      BorderRadius.all(Radius.circular(30));
  static const BorderRadius _containerTopRadius = BorderRadius.only(
    topLeft: Radius.circular(40),
    topRight: Radius.circular(40),
  );

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('assets/videos/Dylearn.mp4')
      ..initialize().then((_) {
        if (_isDisposed) return;

        _cachedAspectRatio = _controller.value.aspectRatio > 0
            ? _controller.value.aspectRatio
            : 16 / 9;

        _controller.setLooping(false);
        _controller.setVolume(0.0);
        _controller.play();

        _isVideoInitialized.value = true;
      }).catchError((error) {
        debugPrint("Error loading video: $error");
      });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _controller.dispose();
    _isVideoInitialized.dispose();
    _isGoogleLoadingNotifier.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleSignIn() async {
    if (!mounted) return;
    _isGoogleLoadingNotifier.value = true;
    try {
      // BUG FIX #3: Gunakan cached _authService
      await _authService.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal Login Google: $e")),
        );
      }
    } finally {
      if (mounted) {
        _isGoogleLoadingNotifier.value = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // RESPONSIVENESS: Ambil responsive helper sekali per build
    final r = context.r;

    return Scaffold(
      body: BackgroundWrapper(
        child: Column(
          children: [
            // RESPONSIVENESS: Ganti hardcoded SizedBox → responsive spacing
            SizedBox(height: r.spacing(20)),
            Expanded(
              flex: 4,
              child: Padding(
                // RESPONSIVENESS: Ganti EdgeInsets.all(24) → responsive
                padding: EdgeInsets.all(r.spacing(24)),
                child: Center(
                  child: RepaintBoundary(
                    child: Container(
                      // OPTIMIZATION: Gunakan cached decoration
                      decoration: _videoContainerDecoration,
                      child: ClipRRect(
                        // OPTIMIZATION: Gunakan cached const BorderRadius
                        borderRadius: _videoClipRadius,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _isVideoInitialized,
                          builder: (context, isInitialized, child) {
                            return AspectRatio(
                              aspectRatio: _cachedAspectRatio,
                              child: isInitialized
                                  ? VideoPlayer(_controller)
                                  : Container(
                                      color: Colors.orange.shade50,
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                            color: Colors.orange),
                                      ),
                                    ),
                            );
                          },
                        ),
                      ),
                    ),
                  ).animate().fadeIn(duration: 600.ms).scale(curve: Curves.easeOutBack, begin: const Offset(0.8, 0.8)), // Animasi masuk memantul pada video
                ),
              ),
            ),
            Expanded(
              flex: 6,
              child: Container(
                width: double.infinity,
                // RESPONSIVENESS: Ganti padding hardcoded → responsive
                padding: EdgeInsets.all(r.spacing(30)),
                decoration: BoxDecoration(
                  color: Colors.white,
                  // OPTIMIZATION: Gunakan cached const BorderRadius
                  borderRadius: _containerTopRadius,
                  boxShadow: [
                    BoxShadow(
                      color: _containerShadowColor,
                      blurRadius: 25,
                      offset: const Offset(0, -10),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        "Selamat Datang di\nDylearn",
                        textAlign: TextAlign.center,
                        // RESPONSIVENESS: Gunakan responsive font size
                        style: GoogleFonts.comicNeue(
                          fontSize: r.font(30),
                          fontWeight: FontWeight.bold,
                          // BUG FIX #1: shade800 → non-nullable, lebih aman
                          color: Colors.orange.shade800,
                          height: 1.2,
                        ),
                      ).animate().fadeIn(delay: 200.ms, duration: 500.ms).slideY(begin: 0.1), // Animasi teks judul
                      
                      SizedBox(height: r.spacing(10)),
                      
                      Text(
                        "Belajar membaca jadi lebih mudah dan menyenangkan!",
                        textAlign: TextAlign.center,
                        // RESPONSIVENESS: Gunakan responsive font size
                        style: TextStyle(
                          fontSize: r.font(14),
                          color: Colors.black87,
                          height: 1.5,
                        ),
                      ).animate().fadeIn(delay: 300.ms, duration: 500.ms).slideY(begin: 0.1), // Animasi teks deskripsi
                      
                      SizedBox(height: r.spacing(25)),
                      
                      _GoogleButton(
                        isLoadingNotifier: _isGoogleLoadingNotifier,
                        onPressed: _handleGoogleSignIn,
                      ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2), // Animasi tombol Google
                      
                      SizedBox(height: r.spacing(15)),
                      
                      Row(
                        children: [
                          Expanded(
                              child: Divider(color: Colors.grey.shade300)),
                          Padding(
                            // RESPONSIVENESS: Ganti horizontal: 10 → responsive
                            padding: EdgeInsets.symmetric(
                                horizontal: r.spacing(10)),
                            child: Text(
                              "ATAU",
                              style: TextStyle(
                                // RESPONSIVENESS: Ganti fontSize: 12 → responsive
                                fontSize: r.font(12),
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                              child: Divider(color: Colors.grey.shade300)),
                        ],
                      ).animate().fadeIn(delay: 500.ms), // Animasi divider
                      
                      SizedBox(height: r.spacing(15)),
                      
                      const _EmailButton().animate().fadeIn(delay: 600.ms).slideY(begin: 0.2), // Animasi tombol Email
                      
                      SizedBox(height: r.spacing(15)),
                      
                      const _RegisterButton().animate().fadeIn(delay: 700.ms).slideY(begin: 0.2), // Animasi tombol Register
                      
                      SizedBox(height: r.spacing(10)),
                    ],
                  ),
                ),
              ),
            ).animate().slideY(begin: 0.3, duration: 600.ms, curve: Curves.easeOutExpo), // Animasi efek meluncur naik pada container bawah
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _GoogleButton
// ─────────────────────────────────────────────
class _GoogleButton extends StatelessWidget {
  final ValueNotifier<bool> isLoadingNotifier;
  final VoidCallback onPressed;

  const _GoogleButton(
      {required this.isLoadingNotifier, required this.onPressed});

  // OPTIMIZATION: Cache ButtonStyle → static final
  // Style tidak pernah berubah, tidak perlu dibuat ulang setiap ValueListenableBuilder rebuild
  static final ButtonStyle _buttonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.grey,
    elevation: 3,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(30),
      side: BorderSide(color: Colors.grey.shade300),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final r = context.r;

    return SizedBox(
      width: double.infinity,
      // RESPONSIVENESS: Ganti height: 55 → responsive
      height: r.size(55),
      child: ValueListenableBuilder<bool>(
        valueListenable: isLoadingNotifier,
        builder: (context, isLoading, child) {
          return ElevatedButton.icon(
            onPressed: isLoading ? null : onPressed,
            icon: isLoading
                ? SizedBox(
                    // RESPONSIVENESS: Ganti hardcoded 20 → responsive
                    width: r.size(20),
                    height: r.size(20),
                    child: const CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.blue),
                  )
                : Image.asset(
                    'assets/images/GOOGLE.png',
                    // RESPONSIVENESS: Ganti height: 24 → responsive
                    height: r.size(24),
                    errorBuilder: (c, e, s) => Icon(
                      Icons.g_mobiledata,
                      // RESPONSIVENESS: Ganti size: 30 → responsive
                      size: r.size(30),
                      color: Colors.blue,
                    ),
                  ),
            label: Text(
              "Masuk dengan Google",
              // RESPONSIVENESS: Gunakan responsive font
              style: GoogleFonts.poppins(
                fontSize: r.font(16),
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            // OPTIMIZATION: Gunakan cached ButtonStyle
            style: _buttonStyle,
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _EmailButton
// ─────────────────────────────────────────────
class _EmailButton extends StatelessWidget {
  const _EmailButton();

  // OPTIMIZATION: Cache ButtonStyle → static final
  static final ButtonStyle _buttonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.orange,
    elevation: 0,
    side: const BorderSide(color: Colors.orange, width: 2),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(30),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final r = context.r;

    return SizedBox(
      width: double.infinity,
      // RESPONSIVENESS: Ganti height: 55 → responsive
      height: r.size(55),
      child: ElevatedButton(
        onPressed: () {
          Navigator.push(context,
              MaterialPageRoute(builder: (c) => const LoginScreen()));
        },
        // OPTIMIZATION: Gunakan cached ButtonStyle
        style: _buttonStyle,
        child: Text(
          "Masuk dengan Email",
          // RESPONSIVENESS: Gunakan responsive font
          style: GoogleFonts.comicNeue(
            fontSize: r.font(18),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _RegisterButton
// ─────────────────────────────────────────────
class _RegisterButton extends StatelessWidget {
  const _RegisterButton();

  // OPTIMIZATION: Cache shadow color → static final
  static final Color _shadowColor = Colors.orange.withOpacity(0.4);

  // OPTIMIZATION: Cache ButtonStyle → static final
  static final ButtonStyle _buttonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.orange,
    foregroundColor: Colors.white,
    elevation: 5,
    shadowColor: _shadowColor,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(30),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final r = context.r;

    return SizedBox(
      width: double.infinity,
      // RESPONSIVENESS: Ganti height: 55 → responsive
      height: r.size(55),
      child: ElevatedButton(
        onPressed: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (c) => const RegisterScreen()));
        },
        // OPTIMIZATION: Gunakan cached ButtonStyle
        style: _buttonStyle,
        child: Text(
          "Buat Akun Baru",
          // RESPONSIVENESS: Gunakan responsive font
          style: GoogleFonts.comicNeue(
            fontSize: r.font(18),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}