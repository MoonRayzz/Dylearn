// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../config/guru_theme.dart';
import '../../../core/utils/responsive_helper.dart';
import 'add_student_screen.dart';
import 'student_analytics_screen.dart';
import 'package:dylearn/features/student/library_screen.dart';
import 'package:dylearn/features/student/camera_picker_screen.dart';
import 'package:dylearn/features/student/upload_pdf_screen.dart';
import 'package:dylearn/features/student/activity_screen.dart';

class StudentListScreen extends StatefulWidget {
  const StudentListScreen({super.key});

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchQuery.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _generatePairingCode(
    BuildContext context,
    String studentUid,
    String studentName,
  ) async {
    Navigator.pop(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: GuruTheme.primary),
      ),
    );
    try {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final random = Random();
      final String code =
          'DYL-${List.generate(6, (_) => chars[random.nextInt(chars.length)]).join()}';

      await FirebaseFirestore.instance.collection('users').doc(studentUid).set({
        'pairingCode': code,
        'pairingCodeCreatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      Navigator.pop(context);
      _showCodeDialog(context, studentName, code);
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal membuat kode: $e'),
          backgroundColor: GuruTheme.errorRed,
        ),
      );
    }
  }

  void _showCodeDialog(BuildContext context, String name, String code) {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Kode Sinkronisasi',
                style: GuruTheme.titleLarge(color: GuruTheme.primary),
              ),
              const SizedBox(height: 12),
              Text(
                'Berikan kode ini kepada $name agar riwayat belajarnya dapat tersinkron.',
                textAlign: TextAlign.center,
                style: GuruTheme.bodyMedium(),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 24,
                ),
                decoration: BoxDecoration(
                  color: GuruTheme.primaryFixed,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  code,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: GuruTheme.primary,
                    letterSpacing: 3,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GuruTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(c),
                  child: Text(
                    'Tutup',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActionSheet(
    BuildContext context,
    String uid,
    String name,
    String accountType,
    ResponsiveHelper r,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: GuruTheme.surfaceLowest,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: GuruTheme.outlineVariant,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: GuruTheme.primaryFixed,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: GuruTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pilih Aksi', style: GuruTheme.titleMedium()),
                        Text(name, style: GuruTheme.bodySmall()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              height: 1,
              color: GuruTheme.surfaceHigh,
            ),

            // Options
            ...[
              _SheetOption(
                icon: Icons.analytics_rounded,
                title: 'Lihat Analitik',
                subtitle: 'Rapor perkembangan membaca',
                color: GuruTheme.primaryContainer,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudentAnalyticsScreen(
                        studentUid: uid,
                        studentName: name,
                      ),
                    ),
                  );
                },
              ),
              _SheetOption(
                icon: Icons.camera_alt_rounded,
                title: 'Scan Kamera',
                subtitle: 'Foto buku fisik langsung',
                color: const Color(0xFF0984E3),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CameraPickerScreen(
                        activeStudentUid: uid,
                        activeStudentName: name,
                      ),
                    ),
                  );
                },
              ),
              _SheetOption(
                icon: Icons.picture_as_pdf_rounded,
                title: 'Upload PDF',
                subtitle: 'Gunakan LKS atau dokumen PDF',
                color: GuruTheme.errorRed,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UploadPdfScreen(
                        activeStudentUid: uid,
                        activeStudentName: name,
                      ),
                    ),
                  );
                },
              ),
              _SheetOption(
                icon: Icons.local_library_rounded,
                title: 'Perpustakaan Aplikasi',
                subtitle: 'Pilih dari buku yang tersedia',
                color: GuruTheme.accentOrange,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LibraryScreen(
                        activeStudentUid: uid,
                        activeStudentName: name,
                      ),
                    ),
                  );
                },
              ),
              _SheetOption(
                icon: Icons.history_edu_rounded,
                title: 'Riwayat Bacaan',
                subtitle: 'Buku yang pernah diberikan',
                color: GuruTheme.successGreen,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ActivityScreen(
                        activeStudentUid: uid,
                        activeStudentName: name,
                      ),
                    ),
                  );
                },
              ),
            ].animate(interval: 40.ms).fadeIn(duration: 250.ms),

            if (accountType == 'managed') ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                height: 1,
                color: GuruTheme.surfaceHigh,
              ),
              _SheetOption(
                icon: Icons.sync_rounded,
                title: 'Buat Kode Sinkronisasi',
                subtitle: 'Pindahkan data ke HP pribadi murid',
                color: const Color(0xFF6C5CE7),
                onTap: () => _generatePairingCode(context, uid, name),
              ).animate().fadeIn(delay: 200.ms),
            ],

            SizedBox(height: 20 + MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Center(child: Text('Sesi tidak valid.'));
    }

    return Scaffold(
      backgroundColor: GuruTheme.surfaceLow,
      appBar: _buildAppBar(context),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('linkedTeacher', arrayContains: _currentUser.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: GuruTheme.primary),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Gagal memuat: ${snapshot.error}',
                style: GuruTheme.bodyMedium(),
              ),
            );
          }

          final allDocs = snapshot.data?.docs ?? [];
          if (allDocs.isEmpty) return _buildEmpty();

          // Hitung summary dari data yg sudah ada — tanpa query tambahan
          // LOGIKA HARUS KONSISTEN dengan status footer di _StudentCard:
          //   "Belum Tersinkron" = managed + pairingCode tidak kosong (kode belum dipakai)
          //   "Tersinkron"       = semua kondisi lain (sudah link atau kode sudah dipakai)
          final int total = allDocs.length;
          final int pending = allDocs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final String accountType = data['accountType'] ?? 'managed';
            final String pairingCode = (data['pairingCode'] ?? '').toString();
            return accountType == 'managed' && pairingCode.isNotEmpty;
          }).length;
          final int synced = total - pending;

          return ValueListenableBuilder<String>(
            valueListenable: _searchQuery,
            builder: (context, query, _) {
              final filtered = allDocs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return (data['displayName'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(query);
              }).toList();

              return CustomScrollView(
                slivers: [
                  // Summary strip
                  SliverToBoxAdapter(
                    child: _SummaryStrip(
                      total: total,
                      synced: synced,
                      pending: pending,
                    ),
                  ),
                  // Section header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      child: Text(
                        'DAFTAR MURID',
                        style: GuruTheme.sectionHeader(),
                      ),
                    ),
                  ),

                  if (filtered.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'Murid tidak ditemukan.',
                          style: GuruTheme.bodyMedium(),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        // padding bawah: floating nav + system inset
                        MediaQuery.of(context).padding.bottom + 64 + 20 + 16,
                      ),
                      sliver: SliverList.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final data =
                              filtered[i].data() as Map<String, dynamic>;
                          final String name =
                              data['displayName'] ?? 'Tanpa Nama';
                          final String uid = filtered[i].id;
                          final String grade = data['grade'] ?? '-';
                          final String dyslexia = data['dyslexiaType'] ?? '-';
                          final String accountType =
                              data['accountType'] ?? 'independent';
                          final String photoUrl = data['photoUrl'] ?? '';
                          final String pairingCode = data['pairingCode'] ?? '';

                          return _StudentCard(
                                name: name,
                                grade: grade,
                                dyslexia: dyslexia,
                                accountType: accountType,
                                photoUrl: photoUrl,
                                pairingCode: pairingCode,
                                onTap: () => _showActionSheet(
                                  context,
                                  uid,
                                  name,
                                  accountType,
                                  context.r,
                                ),
                              )
                              .animate(delay: (i * 50).ms)
                              .fadeIn(duration: 350.ms)
                              .slideY(
                                begin: 0.08,
                                duration: 350.ms,
                                curve: Curves.easeOutQuad,
                              );
                        },
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      // PERBAIKAN: Mengubah tinggi dari 120 menjadi 140
      preferredSize: const Size.fromHeight(140),
      child: Container(
        color: GuruTheme.surfaceLowest,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
                child: Row(
                  children: [
                    Text(
                      'DyLearn',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        foreground: Paint()
                          ..shader = const LinearGradient(
                            colors: [
                              GuruTheme.primary,
                              GuruTheme.primaryContainer,
                            ],
                          ).createShader(const Rect.fromLTWH(0, 0, 120, 30)),
                      ),
                    ),
                    const Spacer(),
                    // Tombol tambah murid di AppBar
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AddStudentScreen(),
                        ),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: GuruTheme.accentOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(
                        'Tambah Murid',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => _searchQuery.value = v.toLowerCase(),
                  style: GuruTheme.bodyMedium(color: GuruTheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Cari nama murid...',
                    hintStyle: GuruTheme.bodyMedium(),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: GuruTheme.outline,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: GuruTheme.surfaceLow,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              // Border bawah primer
              Container(height: 3, color: GuruTheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
                width: 90,
                height: 90,
                decoration: const BoxDecoration(
                  color: Color(0x0F00466C),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.people_outline_rounded,
                  size: 44,
                  color: Color(0x6600466C),
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: -6, end: 6, duration: 2.seconds),
          const SizedBox(height: 20),
          Text(
            'Belum Ada Murid',
            style: GuruTheme.titleLarge(color: const Color(0xFF6B6B80)),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 8),
          Text(
            'Ketuk "+ Tambah Murid" untuk\nmenambahkan data murid baru.',
            textAlign: TextAlign.center,
            style: GuruTheme.bodyMedium(),
          ).animate().fadeIn(delay: 300.ms),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary Strip
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final int total;
  final int synced;
  final int pending;

  const _SummaryStrip({
    required this.total,
    required this.synced,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        children: [
          _SummaryChip(
            icon: Icons.group_rounded,
            label: '$total Murid',
            iconColor: GuruTheme.primary,
            iconBg: GuruTheme.primaryFixed,
          ),
          const SizedBox(width: 10),
          _SummaryChip(
            icon: Icons.check_circle_rounded,
            label: '$synced Tersinkron',
            iconColor: GuruTheme.successGreen,
            iconBg: GuruTheme.successGreenBg,
          ),
          const SizedBox(width: 10),
          _SummaryChip(
            icon: Icons.sync_disabled_rounded,
            label: '$pending Belum Tersinkron',
            iconColor: GuruTheme.warningAmber,
            iconBg: GuruTheme.warningAmberBg,
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color iconBg;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.iconBg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: GuruTheme.surfaceLowest,
        borderRadius: BorderRadius.circular(20),
        boxShadow: GuruTheme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: GuruTheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Student Card
// ─────────────────────────────────────────────────────────────────────────────

class _StudentCard extends StatelessWidget {
  final String name;
  final String grade;
  final String dyslexia;
  final String accountType;
  final String photoUrl;
  final String pairingCode;
  final VoidCallback onTap;

  const _StudentCard({
    required this.name,
    required this.grade,
    required this.dyslexia,
    required this.accountType,
    required this.photoUrl,
    required this.pairingCode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isManaged = accountType == 'managed';
    final Color avatarBg = GuruTheme.avatarColor(name);

    return Container(
      decoration: GuruTheme.cardDecoration,
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: const Color(0x0800466C),
          highlightColor: Colors.transparent,
          child: Column(
            children: [
              // Main row
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: avatarBg,
                      child: photoUrl.isNotEmpty
                          ? ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: photoUrl,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) =>
                                    _InitialText(name: name, fontSize: 16),
                              ),
                            )
                          : _InitialText(name: name, fontSize: 16),
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
                              // Kebab menu → trigger sheet
                              GestureDetector(
                                onTap: onTap,
                                child: const Icon(
                                  Icons.more_vert_rounded,
                                  size: 20,
                                  color: GuruTheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$grade · $dyslexia',
                            style: GuruTheme.bodySmall(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Arrow button
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: GuruTheme.primaryFixed,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: GuruTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),

              // Status footer
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                color: GuruTheme.surfaceLow,
                child: isManaged && pairingCode.isNotEmpty
                    ? Row(
                        children: [
                          Text(
                            'Kode: ',
                            style: GuruTheme.bodySmall(
                              color: GuruTheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            pairingCode,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: GuruTheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.content_copy_rounded,
                            size: 14,
                            color: GuruTheme.primary,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 14,
                            color: GuruTheme.successGreen,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Tersinkron ✓',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: GuruTheme.successGreen,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _InitialText extends StatelessWidget {
  final String name;
  final double fontSize;

  const _InitialText({required this.name, required this.fontSize});

  @override
  Widget build(BuildContext context) => Text(
    name.isNotEmpty ? name[0].toUpperCase() : '?',
    style: GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      color: Colors.white,
    ),
  );
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SheetOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GuruTheme.titleMedium()),
                  const SizedBox(height: 1),
                  Text(subtitle, style: GuruTheme.bodySmall()),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: GuruTheme.outlineVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
