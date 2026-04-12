// ignore_for_file: use_build_context_synchronously, deprecated_member_use, unnecessary_underscores, curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../config/guru_theme.dart';
import '../../../core/services/auth_service.dart';
import '../../auth/auth_wrapper.dart';
import '../../../core/utils/responsive_helper.dart';
import '../../../core/services/export_service.dart';

class GuruSettingsScreen extends StatefulWidget {
  const GuruSettingsScreen({super.key});

  @override
  State<GuruSettingsScreen> createState() => _GuruSettingsScreenState();
}

class _GuruSettingsScreenState extends State<GuruSettingsScreen> {
  final AuthService _authService = AuthService();
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  String _displayName = 'Guru Dylearn';
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _displayName = _currentUser?.displayName ?? 'Guru Dylearn';
    _fetchLatestName();
  }

  // ── Logic: Fetch nama terbaru dari Firestore ────────────────────────────────
  Future<void> _fetchLatestName() async {
    if (_currentUser == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser.uid)
          .get();
      if (doc.exists && mounted) {
        setState(
          () => _displayName = doc.data()?['displayName'] ?? _displayName,
        );
      }
    } catch (e) {
      debugPrint('Gagal fetch profil guru: $e');
    }
  }

  // ── Logic: Logout ─────────────────────────────────────────────────────────
  Future<void> _handleLogout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: GuruTheme.errorRedBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: GuruTheme.errorRed,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text('Keluar Akun?', style: GuruTheme.titleLarge()),
              const SizedBox(height: 8),
              Text(
                'Anda akan keluar dari sesi Guru. Login kembali untuk memantau murid.',
                textAlign: TextAlign.center,
                style: GuruTheme.bodyMedium(),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: GuruTheme.outlineVariant),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Batal', style: GuruTheme.labelMedium()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GuruTheme.errorRed,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Keluar',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ).animate().scale(duration: 280.ms, curve: Curves.easeOutBack),
    );

    if (confirm == true) {
      final navigator = Navigator.of(context);
      navigator.pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const Scaffold(
            backgroundColor: GuruTheme.surface,
            body: Center(
              child: CircularProgressIndicator(color: GuruTheme.primary),
            ),
          ),
          transitionDuration: Duration.zero,
        ),
        (route) => false,
      );
      await _authService.signOut();
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
        (route) => false,
      );
    }
  }

  // ── Logic: Edit Profil bottom sheet ─────────────────────────────────────────
  void _showEditProfileSheet() {
    final ctrl = TextEditingController(text: _displayName);
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: GuruTheme.surfaceLowest,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: GuruTheme.outlineVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Edit Profil', style: GuruTheme.titleLarge()),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  style: GuruTheme.bodyMedium(color: GuruTheme.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Nama Tampilan',
                    labelStyle: GuruTheme.labelMedium(color: GuruTheme.outline),
                    prefixIcon: const Icon(
                      Icons.person_outline_rounded,
                      color: GuruTheme.outline,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: GuruTheme.surfaceLow,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: GuruTheme.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GuruTheme.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: isLoading
                        ? null
                        : () async {
                            final newName = ctrl.text.trim();
                            if (newName.isEmpty) return;
                            setModal(() => isLoading = true);
                            try {
                              await _currentUser?.updateDisplayName(newName);
                              await _currentUser?.reload();
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(_currentUser!.uid)
                                  .set({
                                    'displayName': newName,
                                  }, SetOptions(merge: true));
                              if (mounted) {
                                setState(() => _displayName = newName);
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Profil berhasil diperbarui!',
                                    ),
                                    backgroundColor: GuruTheme.successGreen,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            } catch (e) {
                              setModal(() => isLoading = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Gagal: $e'),
                                  backgroundColor: GuruTheme.errorRed,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            'Simpan Perubahan',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ).animate().slideY(begin: 0.1, duration: 300.ms),
        ),
      ),
    ).whenComplete(() => ctrl.dispose());
  }

  // ── Logic: Ganti Password bottom sheet ──────────────────────────────────────
  void _showChangePasswordSheet() {
    final ctrlOld = TextEditingController();
    final ctrlNew = TextEditingController();
    final ctrlCon = TextEditingController();
    bool isLoading = false;
    bool obsOld = true, obsNew = true, obsCon = true;
    String errMsg = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: GuruTheme.surfaceLowest,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: GuruTheme.outlineVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Ubah Password', style: GuruTheme.titleLarge()),
                const SizedBox(height: 4),
                Text(
                  'Password baru minimal 6 karakter.',
                  style: GuruTheme.bodySmall(),
                ),
                const SizedBox(height: 16),
                if (errMsg.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: GuruTheme.errorRedBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: GuruTheme.errorRed,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errMsg,
                            style: GuruTheme.bodySmall(
                              color: GuruTheme.errorRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().shakeX(duration: 300.ms),
                _PasswordField(
                  label: 'Password Lama',
                  controller: ctrlOld,
                  obscure: obsOld,
                  onToggle: () => setModal(() => obsOld = !obsOld),
                ),
                const SizedBox(height: 12),
                _PasswordField(
                  label: 'Password Baru',
                  controller: ctrlNew,
                  obscure: obsNew,
                  onToggle: () => setModal(() => obsNew = !obsNew),
                ),
                const SizedBox(height: 12),
                _PasswordField(
                  label: 'Konfirmasi Password',
                  controller: ctrlCon,
                  obscure: obsCon,
                  onToggle: () => setModal(() => obsCon = !obsCon),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GuruTheme.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: isLoading
                        ? null
                        : () async {
                            final o = ctrlOld.text;
                            final n = ctrlNew.text;
                            final c = ctrlCon.text;
                            if (o.isEmpty || n.isEmpty || c.isEmpty) {
                              setModal(
                                () => errMsg = 'Semua kolom harus diisi.',
                              );
                              return;
                            }
                            if (n.length < 6) {
                              setModal(
                                () => errMsg =
                                    'Password baru minimal 6 karakter.',
                              );
                              return;
                            }
                            if (n != c) {
                              setModal(
                                () =>
                                    errMsg = 'Konfirmasi password tidak cocok.',
                              );
                              return;
                            }
                            setModal(() {
                              isLoading = true;
                              errMsg = '';
                            });
                            try {
                              final cred = EmailAuthProvider.credential(
                                email: _currentUser!.email!,
                                password: o,
                              );
                              await _currentUser.reauthenticateWithCredential(
                                cred,
                              );
                              await _currentUser.updatePassword(n);
                              if (mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Password berhasil diubah!'),
                                    backgroundColor: GuruTheme.successGreen,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            } on FirebaseAuthException catch (e) {
                              setModal(() {
                                isLoading = false;
                                errMsg =
                                    (e.code == 'wrong-password' ||
                                        e.code == 'invalid-credential')
                                    ? 'Password lama salah.'
                                    : 'Gagal: ${e.message}';
                              });
                            } catch (_) {
                              setModal(() {
                                isLoading = false;
                                errMsg = 'Terjadi kesalahan.';
                              });
                            }
                          },
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            'Update Password',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ).animate().slideY(begin: 0.1, duration: 300.ms),
        ),
      ),
    ).whenComplete(() {
      ctrlOld.dispose();
      ctrlNew.dispose();
      ctrlCon.dispose();
    });
  }

  // ── Logic: Panduan Sinkronisasi dialog ─────────────────────────────────────
  void _showSyncGuide() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cara Sinkronisasi Murid', style: GuruTheme.titleLarge()),
              const SizedBox(height: 16),
              ...[
                ("1", "Pilih murid di tab 'Murid'."),
                ("2", "Ketuk kartu → 'Buat Kode Sinkronisasi'."),
                ("3", "Catat kode DYL-XXXXXX yang muncul."),
                ("4", "Minta anak buka Dylearn di HP-nya."),
                (
                  "5",
                  "Di Pengaturan anak → 'Tautkan Akun Guru' → masukkan kode.",
                ),
              ].map(
                (pair) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: GuruTheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            pair.$1,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            pair.$2,
                            style: GuruTheme.bodyMedium(
                              color: GuruTheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GuruTheme.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Paham',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ).animate().scale(duration: 280.ms, curve: Curves.easeOutBack),
    );
  }

  // ── Logic: Export Excel ────────────────────────────────────────────────────
  Future<void> _handleExport() async {
    setState(() => _isExporting = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sedang menyusun data Excel, mohon tunggu...'),
        backgroundColor: GuruTheme.primaryContainer,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    try {
      final path = await ExportService().exportAllDataToExcel();
      if (mounted)
        await Share.shareXFiles([XFile(path)], text: 'Laporan Riset Dylearn');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengekspor: $e'),
            backgroundColor: GuruTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _currentUser?.email ?? 'Tidak ada email';
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: GuruTheme.surfaceLow,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // App bar
          SliverToBoxAdapter(
            child: Container(
              color: GuruTheme.surfaceLowest,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                      child: Text('Pengaturan', style: GuruTheme.headline()),
                    ),
                    Container(height: 3, color: GuruTheme.primary),
                  ],
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              bottomInset + 64 + 20 + 16,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Profile card
                _ProfileCard(
                  name: _displayName,
                  email: email,
                  onEdit: _showEditProfileSheet,
                ).animate().fadeIn(duration: 350.ms),

                const SizedBox(height: 24),

                // AKUN section
                Text('AKUN', style: GuruTheme.sectionHeader()),
                const SizedBox(height: 10),
                _TileGroup(
                  tiles: [
                    _Tile(
                      icon: Icons.person_outline_rounded,
                      iconBg: GuruTheme.primaryFixed,
                      iconColor: GuruTheme.primary,
                      title: 'Edit Profil',
                      subtitle: 'Nama dan informasi dasar',
                      onTap: _showEditProfileSheet,
                    ),
                    _Tile(
                      icon: Icons.lock_outline_rounded,
                      iconBg: GuruTheme.primaryFixed,
                      iconColor: GuruTheme.primary,
                      title: 'Ganti Password',
                      subtitle: 'Ubah kata sandi akun',
                      onTap: _showChangePasswordSheet,
                    ),
                  ],
                ).animate(delay: 100.ms).fadeIn(duration: 350.ms),

                const SizedBox(height: 20),

                // DATA section
                Text('DATA & LAPORAN', style: GuruTheme.sectionHeader()),
                const SizedBox(height: 10),
                _TileGroup(
                  tiles: [
                    _Tile(
                      icon: Icons.download_rounded,
                      iconBg: GuruTheme.successGreenBg,
                      iconColor: GuruTheme.successGreen,
                      title: _isExporting
                          ? 'Sedang Mengekspor...'
                          : 'Export Data Excel',
                      subtitle: 'Unduh laporan semua murid (.xlsx)',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: GuruTheme.successGreenBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'EXCEL',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: GuruTheme.successGreen,
                          ),
                        ),
                      ),
                      onTap: _isExporting ? () {} : _handleExport,
                    ),
                    _Tile(
                      icon: Icons.qr_code_2_rounded,
                      iconBg: GuruTheme.warningAmberBg,
                      iconColor: GuruTheme.warningAmber,
                      title: 'Panduan Sinkronisasi',
                      subtitle: 'Cara menghubungkan akun murid',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: GuruTheme.primaryFixed,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'INFO',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: GuruTheme.primary,
                          ),
                        ),
                      ),
                      onTap: _showSyncGuide,
                    ),
                  ],
                ).animate(delay: 200.ms).fadeIn(duration: 350.ms),

                const SizedBox(height: 20),

                // LAINNYA section
                Text('LAINNYA', style: GuruTheme.sectionHeader()),
                const SizedBox(height: 10),
                _TileGroup(
                  tiles: [
                    _Tile(
                      icon: Icons.logout_rounded,
                      iconBg: GuruTheme.errorRedBg,
                      iconColor: GuruTheme.errorRed,
                      title: 'Keluar dari Akun',
                      subtitle: 'Sesi akan diakhiri',
                      titleColor: GuruTheme.errorRed,
                      onTap: _handleLogout,
                    ),
                  ],
                ).animate(delay: 300.ms).fadeIn(duration: 350.ms),

                const SizedBox(height: 28),
                Center(
                  child: Text(
                    'DyLearn v1.0.0 · Penelitian Skripsi Undiksha',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: GuruTheme.outline,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Card
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final String name;
  final String email;
  final VoidCallback onEdit;

  const _ProfileCard({
    required this.name,
    required this.email,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: GuruTheme.cardDecoration,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: GuruTheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'G',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GuruTheme.titleMedium(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: GuruTheme.primaryFixed,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'GURU',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: GuruTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GuruTheme.bodySmall(),
                ),
              ],
            ),
          ),

          // Edit button
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onEdit,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: GuruTheme.surfaceLow,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.edit_rounded,
                size: 16,
                color: GuruTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile Group & Tile
// ─────────────────────────────────────────────────────────────────────────────

class _TileGroup extends StatelessWidget {
  final List<_Tile> tiles;
  const _TileGroup({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: GuruTheme.cardDecoration,
      child: Column(
        children: List.generate(tiles.length * 2 - 1, (i) {
          if (i.isOdd) {
            return const Divider(
              height: 1,
              indent: 60,
              color: GuruTheme.surfaceHigh,
            );
          }
          return tiles[i ~/ 2];
        }),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback onTap;

  const _Tile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.titleColor,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GuruTheme.titleMedium(color: titleColor)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: GuruTheme.bodySmall()),
                ],
              ),
            ),
            if (trailing != null) ...[
              trailing!,
            ] else ...[
              const Icon(
                Icons.chevron_right_rounded,
                color: GuruTheme.outlineVariant,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Password Field helper
// ─────────────────────────────────────────────────────────────────────────────

class _PasswordField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;

  const _PasswordField({
    required this.label,
    required this.controller,
    required this.obscure,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: GuruTheme.bodyMedium(color: GuruTheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GuruTheme.labelMedium(color: GuruTheme.outline),
        filled: true,
        fillColor: GuruTheme.surfaceLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: GuruTheme.primary, width: 2),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: GuruTheme.outline,
            size: 20,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}
