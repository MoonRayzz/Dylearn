// ignore_for_file: curly_braces_in_flow_control_structures, deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart'; // DITAMBAHKAN untuk animasi halus
import '../../core/services/auth_service.dart';
import '../../shared/widgets/system_popup.dart';
import '../../core/utils/responsive_helper.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _isPasswordVisibleNotifier = ValueNotifier(false);
  final ValueNotifier<String?> _errorMessageNotifier = ValueNotifier(null);

  static const String _registerErrorMessage =
      'Belum bisa membuat akun.\nCoba periksa lagi ya 😊';

  // ── DESIGN TOKENS ─────────────────────────
  static const Color _primary    = Color(0xFFFF9F1C);
  static const Color _secondary  = Color(0xFF2EC4B6);
  static const Color _background = Color(0xFFFFFBE6);
  static const Color _textDark   = Color(0xFF2D3436);
  static const Color _textMuted  = Color(0xFF636E72);
  static const Color _border     = Color(0xFFE9ECEF);
  static const Color _inputFill  = Color(0xFFFFFDF5);
  static const Color _errorColor = Color(0xFFE74C3C);

  static final ButtonStyle _registerButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: _primary,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    ),
    elevation: 0,
  );

  static const BorderRadius _inputBorderRadius =
      BorderRadius.all(Radius.circular(14));
  static const BorderRadius _containerTopRadius = BorderRadius.only(
    topLeft: Radius.circular(32),
    topRight: Radius.circular(32),
  );
  static const BorderRadius _dragHandleRadius =
      BorderRadius.all(Radius.circular(10));

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _isLoadingNotifier.dispose();
    _isPasswordVisibleNotifier.dispose();
    _errorMessageNotifier.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    _isLoadingNotifier.value = true;
    _errorMessageNotifier.value = null;

    try {
      await _authService.registerWithEmail(
        _emailController.text.trim(),
        _passwordController.text.trim(),
        _nameController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _errorMessageNotifier.value = _registerErrorMessage;
      showSystemPopup(
        context: context,
        type: PopupType.error,
        title: 'Belum Berhasil',
        message: _registerErrorMessage,
      );
    } finally {
      if (mounted) _isLoadingNotifier.value = false;
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
                  top: -r.size(50),
                  left: -r.size(50),
                  child: Container(
                    width: r.size(220),
                    height: r.size(220),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.12),
                    ),
                  ),
                ),
                Positioned(
                  top: r.size(20),
                  right: -r.size(30),
                  child: Container(
                    width: r.size(100),
                    height: r.size(100),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _secondary.withOpacity(0.2),
                    ),
                  ),
                ),
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
                            'Buat Akun Baru ✨',
                            style: GoogleFonts.poppins(
                              fontSize: r.font(22),
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                              height: 1.2,
                            ),
                          ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1),
                          Text(
                            'Daftarkan dirimu, gratis!',
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
              height: size.height * 0.82,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _background,
                borderRadius: _containerTopRadius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -10),
                  )
                ]
              ),
              child: ClipRRect(
                borderRadius: _containerTopRadius,
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(r.spacing(24), r.spacing(8), r.spacing(24), r.spacing(16)),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: r.size(40),
                            height: r.size(4),
                            margin: EdgeInsets.only(top: r.spacing(12), bottom: r.spacing(20)),
                            decoration: BoxDecoration(
                              color: _primary.withOpacity(0.3),
                              borderRadius: _dragHandleRadius,
                            ),
                          ),
                        ),

                        // Trust badge berdimensi
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: r.spacing(12), vertical: r.spacing(8)),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: _secondary.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ],
                            border: Border.all(color: _secondary.withOpacity(0.1)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_outlined, color: _secondary, size: r.size(15)),
                              SizedBox(width: r.spacing(6)),
                              Text(
                                'Gratis · Daftar hanya dalam 1 menit',
                                style: GoogleFonts.poppins(
                                  fontSize: r.font(12),
                                  color: _secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ).animate(delay: 350.ms).fadeIn().slideY(begin: 0.2),

                        SizedBox(height: r.spacing(20)),

                        Text(
                          'Informasi Akun',
                          style: GoogleFonts.poppins(
                            fontSize: r.font(20),
                            fontWeight: FontWeight.w700,
                            color: _textDark,
                            letterSpacing: -0.2,
                          ),
                        ).animate(delay: 400.ms).fadeIn().slideX(begin: -0.1),
                        SizedBox(height: r.spacing(4)),
                        Text(
                          'Isi semua data di bawah ini dengan benar.',
                          style: GoogleFonts.poppins(fontSize: r.font(13), color: _textMuted),
                        ).animate(delay: 450.ms).fadeIn(),
                        SizedBox(height: r.spacing(20)),

                        // Form Fields dengan Staggered Animation
                        _buildLabel('Nama Lengkap', r).animate(delay: 500.ms).fadeIn(),
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          style: GoogleFonts.poppins(fontSize: r.font(14), color: _textDark),
                          decoration: _buildInputDecoration('Masukkan nama lengkap', Icons.person_outline_rounded, r),
                          validator: (v) => v!.isEmpty ? 'Nama belum diisi' : null,
                        ).animate(delay: 500.ms).fadeIn().slideY(begin: 0.1),
                        
                        SizedBox(height: r.spacing(14)),

                        _buildLabel('Email', r).animate(delay: 550.ms).fadeIn(),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          style: GoogleFonts.poppins(fontSize: r.font(14), color: _textDark),
                          decoration: _buildInputDecoration('contoh@email.com', Icons.mail_outline_rounded, r),
                          validator: (v) => v!.isEmpty || !v.contains('@') ? 'Email belum benar' : null,
                        ).animate(delay: 550.ms).fadeIn().slideY(begin: 0.1),
                        
                        SizedBox(height: r.spacing(14)),

                        _buildLabel('Kata Sandi', r).animate(delay: 600.ms).fadeIn(),
                        ValueListenableBuilder<bool>(
                          valueListenable: _isPasswordVisibleNotifier,
                          builder: (context, isVisible, child) {
                            return TextFormField(
                              controller: _passwordController,
                              obscureText: !isVisible,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _handleRegister(),
                              style: GoogleFonts.poppins(fontSize: r.font(14), color: _textDark),
                              decoration: _buildInputDecoration('Minimal 6 karakter', Icons.lock_outline_rounded, r).copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(isVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: _textMuted, size: r.size(20)),
                                  onPressed: () => _isPasswordVisibleNotifier.value = !_isPasswordVisibleNotifier.value,
                                ),
                              ),
                              validator: (v) => v!.length < 6 ? 'Minimal 6 huruf ya' : null,
                            );
                          },
                        ).animate(delay: 600.ms).fadeIn().slideY(begin: 0.1),
                        
                        Padding(
                          padding: EdgeInsets.only(top: r.spacing(6), left: r.spacing(4)),
                          child: Row(
                            children: [
                              Icon(Icons.shield_outlined, size: r.size(12), color: _textMuted),
                              SizedBox(width: r.spacing(5)),
                              Text(
                                'Gunakan kombinasi huruf dan angka.',
                                style: GoogleFonts.poppins(fontSize: r.font(11), color: _textMuted),
                              ),
                            ],
                          ),
                        ).animate(delay: 650.ms).fadeIn(),

                        ValueListenableBuilder<String?>(
                          valueListenable: _errorMessageNotifier,
                          builder: (context, errorMsg, child) {
                            if (errorMsg == null) return const SizedBox.shrink();
                            return Container(
                              margin: EdgeInsets.only(top: r.spacing(12)),
                              padding: EdgeInsets.all(r.spacing(12)),
                              decoration: BoxDecoration(
                                color: _errorColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _errorColor.withOpacity(0.25)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline_rounded, color: _errorColor, size: r.size(16)),
                                  SizedBox(width: r.spacing(8)),
                                  Expanded(child: Text(errorMsg, style: GoogleFonts.poppins(color: _errorColor, fontSize: r.font(12), fontWeight: FontWeight.w500))),
                                ],
                              ),
                            ).animate().shakeX();
                          },
                        ),

                        SizedBox(height: r.spacing(28)),

                        ValueListenableBuilder<bool>(
                          valueListenable: _isLoadingNotifier,
                          builder: (context, isLoading, child) {
                            return SizedBox(
                              width: double.infinity,
                              height: r.size(54),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    if(!isLoading) BoxShadow(color: _primary.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))
                                  ]
                                ),
                                child: ElevatedButton(
                                  onPressed: isLoading ? null : _handleRegister,
                                  style: _registerButtonStyle,
                                  child: isLoading
                                      ? SizedBox(width: r.size(20), height: r.size(20), child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : Text(
                                          'Buat Akun',
                                          style: GoogleFonts.poppins(fontSize: r.font(15), fontWeight: FontWeight.w700, color: Colors.white),
                                        ),
                                ),
                              ),
                            );
                          },
                        ).animate(delay: 700.ms).fadeIn().scale(curve: Curves.easeOutBack),

                        SizedBox(height: r.spacing(20)),

                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Sudah punya akun? ', style: GoogleFonts.poppins(color: _textMuted, fontSize: r.font(13))),
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Text(
                                  'Masuk',
                                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: _primary, fontSize: r.font(13)),
                                ),
                              ),
                            ],
                          ),
                        ).animate(delay: 800.ms).fadeIn(),
                        SizedBox(height: r.spacing(8)),
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

  Widget _buildLabel(String text, ResponsiveHelper r) {
    return Padding(
      padding: EdgeInsets.only(bottom: r.spacing(8), left: r.spacing(2)),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          fontSize: r.font(13),
          color: _textDark,
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String hint, IconData icon, ResponsiveHelper r) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.poppins(fontSize: r.font(14), color: _textMuted),
      prefixIcon: Icon(icon, color: _primary, size: r.size(20)),
      filled: true,
      fillColor: _inputFill,
      contentPadding: EdgeInsets.symmetric(vertical: r.spacing(16)),
      border: OutlineInputBorder(borderRadius: _inputBorderRadius, borderSide: const BorderSide(color: _border)),
      enabledBorder: OutlineInputBorder(borderRadius: _inputBorderRadius, borderSide: const BorderSide(color: _border)),
      focusedBorder: const OutlineInputBorder(borderRadius: _inputBorderRadius, borderSide: BorderSide(color: _primary, width: 1.8)),
      errorBorder: const OutlineInputBorder(borderRadius: _inputBorderRadius, borderSide: BorderSide(color: _errorColor, width: 1.0)),
      focusedErrorBorder: const OutlineInputBorder(borderRadius: _inputBorderRadius, borderSide: BorderSide(color: _errorColor, width: 1.5)),
    );
  }
}