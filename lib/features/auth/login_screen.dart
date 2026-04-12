// ignore_for_file: curly_braces_in_flow_control_structures, use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart'; // DITAMBAHKAN untuk animasi
import '../../core/services/auth_service.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import '../../shared/widgets/system_popup.dart';
import '../../core/utils/responsive_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  final AuthService _authService = AuthService();

  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _isPasswordVisibleNotifier = ValueNotifier(false);
  final ValueNotifier<String?> _errorMessageNotifier = ValueNotifier(null);

  static const String _friendlyLoginError =
      'Email atau kata sandi belum benar.\nCoba pelan-pelan lagi ya 😊';

  // ── DESIGN TOKENS ─────────────────────────
  static const Color _primary    = Color(0xFFFF9F1C);
  static const Color _secondary  = Color(0xFF2EC4B6);
  static const Color _background = Color(0xFFFFFBE6);
  static const Color _textDark   = Color(0xFF2D3436);
  static const Color _textMuted  = Color(0xFF636E72);
  static const Color _border     = Color(0xFFE9ECEF);
  static const Color _inputFill  = Color(0xFFFFFDF5);
  static const Color _errorColor = Color(0xFFE74C3C);

  static final ButtonStyle _loginButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: _primary,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    ),
    elevation: 0,
  );

  static final ButtonStyle _googleButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: _textDark,
    backgroundColor: Colors.white,
    side: const BorderSide(color: _border, width: 1.5),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    ),
  );

  static const BorderRadius _inputBorderRadius =
      BorderRadius.all(Radius.circular(14));
  static const BorderRadius _containerTopRadius = BorderRadius.only(
    topLeft: Radius.circular(32),
    topRight: Radius.circular(32),
  );
  static const BorderRadius _dragHandleRadius =
      BorderRadius.all(Radius.circular(10));

  static final Widget _googleIcon = Image.asset(
    'assets/images/GOOGLE.png',
    height: 20,
    errorBuilder: (c, e, s) => const Icon(Icons.login, size: 20),
  );

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _isLoadingNotifier.dispose();
    _isPasswordVisibleNotifier.dispose();
    _errorMessageNotifier.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    _isLoadingNotifier.value = true;
    _errorMessageNotifier.value = null;

    try {
      await _authService.loginWithEmail(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _errorMessageNotifier.value = _friendlyLoginError;
      showSystemPopup(
        context: context,
        type: PopupType.error,
        title: 'Belum Bisa Masuk',
        message: _friendlyLoginError,
      );
    } finally {
      if (mounted) _isLoadingNotifier.value = false;
    }
  }

  Future<void> _handleGoogleLogin() async {
    _isLoadingNotifier.value = true;
    _errorMessageNotifier.value = null;

    try {
      await _authService.signInWithGoogle();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _errorMessageNotifier.value = 'Belum bisa masuk.\nCoba lagi ya 😊';
      showSystemPopup(
        context: context,
        type: PopupType.error,
        title: 'Belum Bisa Masuk',
        message: 'Login Google belum berhasil.\nCoba lagi sebentar ya.',
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
                  top: -r.size(80),
                  right: -r.size(80),
                  child: Container(
                    width: r.size(280),
                    height: r.size(280),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.13),
                    ),
                  ),
                ),
                Positioned(
                  top: r.size(30),
                  left: -r.size(35),
                  child: Container(
                    width: r.size(110),
                    height: r.size(110),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _secondary.withOpacity(0.22),
                    ),
                  ),
                ),
                Positioned(
                  top: size.height * 0.07,
                  left: r.spacing(28),
                  right: r.spacing(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: r.spacing(12),
                          vertical: r.spacing(6),
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.menu_book_rounded, color: Colors.white, size: r.size(14)),
                            SizedBox(width: r.spacing(6)),
                            Text(
                              'DyLearn',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: r.font(12),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(duration: 500.ms).slideX(begin: -0.2),
                      SizedBox(height: r.spacing(16)),
                      Text(
                        'Halo,\nSelamat Datang! 👋',
                        style: GoogleFonts.poppins(
                          fontSize: r.font(30),
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.2,
                          letterSpacing: -0.3,
                        ),
                      ).animate().fadeIn(delay: 100.ms, duration: 500.ms).slideY(begin: 0.2),
                      SizedBox(height: r.spacing(8)),
                      Text(
                        'Masuk untuk melanjutkan perjalanan belajarmu.',
                        style: GoogleFonts.poppins(
                          color: Colors.white.withOpacity(0.88),
                          fontSize: r.font(13),
                          height: 1.5,
                        ),
                      ).animate().fadeIn(delay: 200.ms, duration: 500.ms),
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
              height: size.height * 0.67,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _background,
                borderRadius: _containerTopRadius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
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
                            margin: EdgeInsets.only(top: r.spacing(12), bottom: r.spacing(24)),
                            decoration: BoxDecoration(
                              color: _primary.withOpacity(0.3),
                              borderRadius: _dragHandleRadius,
                            ),
                          ),
                        ),

                        Text(
                          'Masuk ke Akun',
                          style: GoogleFonts.poppins(
                            fontSize: r.font(20),
                            fontWeight: FontWeight.w700,
                            color: _textDark,
                            letterSpacing: -0.2,
                          ),
                        ).animate(delay: 300.ms).fadeIn().slideX(begin: -0.1),
                        SizedBox(height: r.spacing(4)),
                        Text(
                          'Gunakan email dan kata sandi kamu.',
                          style: GoogleFonts.poppins(fontSize: r.font(13), color: _textMuted),
                        ).animate(delay: 350.ms).fadeIn(),
                        SizedBox(height: r.spacing(24)),

                        // Form Fields
                        _buildLabel('Email', r).animate(delay: 400.ms).fadeIn(),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          style: GoogleFonts.poppins(fontSize: r.font(14), color: _textDark),
                          decoration: _buildInputDecoration('contoh@email.com', Icons.mail_outline_rounded, r),
                          validator: (v) => v!.isEmpty || !v.contains('@') ? 'Email belum benar' : null,
                        ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.1),
                        
                        SizedBox(height: r.spacing(16)),

                        _buildLabel('Kata Sandi', r).animate(delay: 450.ms).fadeIn(),
                        ValueListenableBuilder<bool>(
                          valueListenable: _isPasswordVisibleNotifier,
                          builder: (context, isVisible, child) {
                            return TextFormField(
                              controller: _passwordController,
                              obscureText: !isVisible,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _handleLogin(),
                              style: GoogleFonts.poppins(fontSize: r.font(14), color: _textDark),
                              decoration: _buildInputDecoration('Masukkan kata sandi', Icons.lock_outline_rounded, r).copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(isVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: _textMuted, size: r.size(20)),
                                  onPressed: () => _isPasswordVisibleNotifier.value = !_isPasswordVisibleNotifier.value,
                                ),
                              ),
                              validator: (v) => v!.isEmpty ? 'Isi kata sandi dulu ya' : null,
                            );
                          },
                        ).animate(delay: 450.ms).fadeIn().slideY(begin: 0.1),

                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            style: TextButton.styleFrom(foregroundColor: _primary),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const ForgotPasswordScreen())),
                            child: Text('Lupa Kata Sandi?', style: GoogleFonts.poppins(fontSize: r.font(12), fontWeight: FontWeight.w600, color: _primary)),
                          ),
                        ).animate(delay: 500.ms).fadeIn(),

                        // Error message
                        ValueListenableBuilder<String?>(
                          valueListenable: _errorMessageNotifier,
                          builder: (context, errorMsg, child) {
                            if (errorMsg == null) return const SizedBox.shrink();
                            return Container(
                              margin: EdgeInsets.only(bottom: r.spacing(10)),
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

                        // Buttons
                        ValueListenableBuilder<bool>(
                          valueListenable: _isLoadingNotifier,
                          builder: (context, isLoading, child) {
                            return Column(
                              children: [
                                SizedBox(
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
                                      onPressed: isLoading ? null : _handleLogin,
                                      style: _loginButtonStyle,
                                      child: isLoading
                                          ? SizedBox(width: r.size(20), height: r.size(20), child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                          : Text('Masuk', style: GoogleFonts.poppins(fontSize: r.font(15), fontWeight: FontWeight.w700, color: Colors.white)),
                                    ),
                                  ),
                                ).animate(delay: 550.ms).fadeIn().scale(curve: Curves.easeOutBack),
                                
                                SizedBox(height: r.spacing(16)),

                                Row(
                                  children: [
                                    const Expanded(child: Divider(color: _border, thickness: 1)),
                                    Padding(
                                      padding: EdgeInsets.symmetric(horizontal: r.spacing(12)),
                                      child: Text('atau', style: GoogleFonts.poppins(fontSize: r.font(12), color: _textMuted)),
                                    ),
                                    const Expanded(child: Divider(color: _border, thickness: 1)),
                                  ],
                                ).animate(delay: 600.ms).fadeIn(),
                                
                                SizedBox(height: r.spacing(16)),

                                SizedBox(
                                  width: double.infinity,
                                  height: r.size(52),
                                  child: OutlinedButton.icon(
                                    onPressed: isLoading ? null : _handleGoogleLogin,
                                    style: _googleButtonStyle,
                                    icon: _googleIcon,
                                    label: Text('Masuk dengan Google', style: GoogleFonts.poppins(fontSize: r.font(14), fontWeight: FontWeight.w500, color: _textDark)),
                                  ),
                                ).animate(delay: 650.ms).fadeIn().slideY(begin: 0.2),
                              ],
                            );
                          },
                        ),

                        SizedBox(height: r.spacing(24)),

                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Belum punya akun? ', style: GoogleFonts.poppins(color: _textMuted, fontSize: r.font(13))),
                              GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const RegisterScreen())),
                                child: Text('Daftar Sekarang', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: _primary, fontSize: r.font(13))),
                              ),
                            ],
                          ),
                        ).animate(delay: 750.ms).fadeIn(),
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
        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: r.font(13), color: _textDark),
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