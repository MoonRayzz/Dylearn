// ignore_for_file: curly_braces_in_flow_control_structures, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart'; // DITAMBAHKAN untuk animasi

import '../../shared/widgets/system_popup.dart';
import '../../core/utils/responsive_helper.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _emailController;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isLoading = false;

  // ── DESIGN TOKENS ─────────────────────────
  static const Color _primary    = Color(0xFFFF9F1C);
  static const Color _secondary  = Color(0xFF2EC4B6);
  static const Color _background = Color(0xFFFFFBE6);
  static const Color _textDark   = Color(0xFF2D3436);
  static const Color _textMuted  = Color(0xFF636E72);
  static const Color _border     = Color(0xFFE9ECEF);
  static const Color _inputFill  = Color(0xFFFFFDF5);
  static const Color _errorColor = Color(0xFFE74C3C);

  static final RegExp _emailRegex = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$');

  static final ButtonStyle _sendButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: _primary,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    ),
    elevation: 0,
  );

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      showSystemPopup(
        context: context,
        type: PopupType.warning,
        title: 'Email Belum Benar',
        message: 'Tolong isi email dengan format yang benar.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text.trim(),
      );

      if (!mounted) return;

      showSystemPopup(
        context: context,
        type: PopupType.success,
        title: 'Email Terkirim',
        message: 'Cek email kamu untuk mengatur ulang kata sandi.',
        onConfirm: () {
          Navigator.pop(context);
        },
      );
    } catch (e) {
      if (!mounted) return;

      showSystemPopup(
        context: context,
        type: PopupType.error,
        title: 'Gagal Mengirim',
        message: 'Terjadi kesalahan. Coba lagi nanti.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final r = context.r;

    return Scaffold(
      backgroundColor: _primary,
      body: Stack(
        children: [
          // ── DECORATIVE BACKGROUND ──────────────────────────────
          RepaintBoundary(
            child: Stack(
              children: [
                Positioned(
                  top: -r.size(70),
                  right: -r.size(70),
                  child: Container(
                    width: r.size(240),
                    height: r.size(240),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.12),
                    ),
                  ),
                ),
                Positioned(
                  top: r.size(20),
                  left: -r.size(35),
                  child: Container(
                    width: r.size(100),
                    height: r.size(100),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _secondary.withOpacity(0.22),
                    ),
                  ),
                ),
                // Header Content
                Positioned(
                  top: size.height * 0.065,
                  left: r.spacing(8),
                  right: r.spacing(24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Container(
                          width: r.size(36),
                          height: r.size(36),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                            ),
                          ),
                          child: Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: r.size(18),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      SizedBox(width: r.spacing(6)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lupa Kata Sandi 🔑',
                            style: GoogleFonts.poppins(
                              fontSize: r.font(22),
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                              height: 1.2,
                            ),
                          ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1),
                          Text(
                            'Kami bantu atur ulang kata sandimu.',
                            style: GoogleFonts.poppins(
                              fontSize: r.font(13),
                              color: Colors.white.withOpacity(0.82),
                            ),
                          ).animate(delay: 100.ms).fadeIn(),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── BOTTOM SHEET FORM ──────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: size.height * 0.73,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _background,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -10),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(r.spacing(24), r.spacing(8), r.spacing(24), r.spacing(24)),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: r.size(40),
                            height: r.size(4),
                            margin: EdgeInsets.only(top: r.spacing(12), bottom: r.spacing(24)),
                            decoration: BoxDecoration(
                              color: _primary.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),

                        // Info card modeled look
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(r.spacing(18)),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: _primary.withOpacity(0.1),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              )
                            ],
                            border: Border.all(color: _primary.withOpacity(0.05)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: r.size(48),
                                height: r.size(48),
                                decoration: BoxDecoration(
                                  color: _primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.lock_reset_rounded,
                                  color: _primary,
                                  size: 24,
                                ),
                              ),
                              SizedBox(width: r.spacing(14)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Jangan Panik! 😊',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w700,
                                        fontSize: r.font(15),
                                        color: _textDark,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Masukkan email dan kami akan kirimkan link untuk reset kata sandi.',
                                      style: GoogleFonts.poppins(
                                        fontSize: r.font(12),
                                        color: _textMuted,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.2),

                        SizedBox(height: r.spacing(28)),

                        Text(
                          'Email Terdaftar',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            fontSize: r.font(20),
                            color: _textDark,
                            letterSpacing: -0.2,
                          ),
                        ).animate(delay: 400.ms).fadeIn().slideX(begin: -0.1),
                        const SizedBox(height: 4),
                        Text(
                          'Pastikan email yang kamu masukkan sudah benar.',
                          style: GoogleFonts.poppins(fontSize: r.font(13), color: _textMuted),
                        ).animate(delay: 450.ms).fadeIn(),
                        
                        SizedBox(height: r.spacing(20)),

                        // Label & Input
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, left: 2),
                          child: Text(
                            'Alamat Email',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: r.font(13),
                              color: _textDark,
                            ),
                          ),
                        ).animate(delay: 500.ms).fadeIn(),

                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _sendResetLink(),
                          style: GoogleFonts.poppins(fontSize: r.font(14), color: _textDark),
                          decoration: InputDecoration(
                            hintText: 'contoh@email.com',
                            hintStyle: GoogleFonts.poppins(fontSize: r.font(14), color: _textMuted),
                            prefixIcon: const Icon(Icons.mail_outline_rounded, color: _primary, size: 20),
                            filled: true,
                            fillColor: _inputFill,
                            contentPadding: const EdgeInsets.symmetric(vertical: 16),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _border)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _primary, width: 1.8)),
                            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _errorColor, width: 1.0)),
                            focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _errorColor, width: 1.5)),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Email wajib diisi';
                            if (!_emailRegex.hasMatch(v)) return 'Format email tidak valid';
                            return null;
                          },
                        ).animate(delay: 500.ms).fadeIn().slideY(begin: 0.1),

                        SizedBox(height: r.spacing(12)),

                        // Spam tip
                        Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, size: 13, color: _textMuted),
                            const SizedBox(width: 6),
                            Text(
                              'Periksa folder spam jika email tidak ditemukan.',
                              style: GoogleFonts.poppins(fontSize: r.font(11), color: _textMuted),
                            ),
                          ],
                        ).animate(delay: 550.ms).fadeIn(),

                        SizedBox(height: r.spacing(32)),

                        // Send button with modeled shadow
                        SizedBox(
                          width: double.infinity,
                          height: r.size(54),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                if (!_isLoading)
                                  BoxShadow(
                                    color: _primary.withOpacity(0.35),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  )
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _sendResetLink,
                              style: _sendButtonStyle,
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20, width: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Kirim Link Reset',
                                          style: GoogleFonts.poppins(
                                            fontSize: r.font(15),
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ).animate(delay: 600.ms).fadeIn().scale(curve: Curves.easeOutBack),

                        SizedBox(height: r.spacing(20)),

                        // Back to login
                        Center(
                          child: TextButton.icon(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(foregroundColor: _textMuted),
                            icon: const Icon(Icons.arrow_back_rounded, size: 15),
                            label: Text(
                              'Kembali ke halaman masuk',
                              style: GoogleFonts.poppins(
                                fontSize: r.font(13),
                                color: _textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ).animate(delay: 700.ms).fadeIn(),
                      ],
                    ),
                  ),
                ),
              ),
            ).animate().slideY(begin: 0.4, duration: 600.ms, curve: Curves.easeOutExpo),
          ),
        ],
      ),
    );
  }
}