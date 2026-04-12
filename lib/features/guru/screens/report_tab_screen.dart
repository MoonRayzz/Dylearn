// ignore_for_file: deprecated_member_use, unnecessary_underscores

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../config/guru_theme.dart';
import 'student_analytics_screen.dart';

class ReportTabScreen extends StatefulWidget {
  const ReportTabScreen({super.key});

  @override
  State<ReportTabScreen> createState() => _ReportTabScreenState();
}

class _ReportTabScreenState extends State<ReportTabScreen> {
  final ValueNotifier<String> _searchQuery = ValueNotifier<String>('');
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchQuery.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Sesi tidak valid.'));
    }

    return Scaffold(
      backgroundColor: GuruTheme.surfaceLow,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('linkedTeacher', arrayContains: user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          final allDocs = snapshot.data?.docs ?? [];
          final isLoading =
              snapshot.connectionState == ConnectionState.waiting;

          return CustomScrollView(
            slivers: [
              // Header sebagai SliverPersistentHeader agar search tetap saat scroll
              SliverToBoxAdapter(
                child: _Header(
                  totalCount: allDocs.length,
                  isLoading: isLoading,
                  controller: _searchCtrl,
                  onSearch: (v) => _searchQuery.value = v.toLowerCase(),
                ),
              ),

              if (isLoading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: GuruTheme.primary),
                  ),
                )
              else if (snapshot.hasError)
                SliverFillRemaining(
                  child: Center(
                    child: Text('Gagal memuat: ${snapshot.error}',
                        style: GuruTheme.bodyMedium()),
                  ),
                )
              else if (allDocs.isEmpty)
                SliverFillRemaining(child: _buildEmpty())
              else
                ValueListenableBuilder<String>(
                  valueListenable: _searchQuery,
                  builder: (context, query, _) {
                    final filtered = allDocs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      return (data['displayName'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(query);
                    }).toList();

                    if (filtered.isEmpty) {
                      return SliverFillRemaining(
                        child: Center(
                          child: Text('Murid tidak ditemukan.',
                              style: GuruTheme.bodyMedium()),
                        ),
                      );
                    }

                    return SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                          20,
                          8,
                          20,
                          MediaQuery.of(context).padding.bottom + 64 + 20 + 16),
                      sliver: SliverList.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final data =
                              filtered[i].data() as Map<String, dynamic>;
                          final String name =
                              data['displayName'] ?? 'Tanpa Nama';
                          final String uid = filtered[i].id;
                          final String grade = data['grade'] ?? '-';
                          final String dyslexia =
                              data['dyslexiaType'] ?? '-';

                          return _ReportCard(
                            name: name,
                            grade: grade,
                            dyslexia: dyslexia,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StudentAnalyticsScreen(
                                    studentUid: uid, studentName: name),
                              ),
                            ),
                          )
                              .animate(delay: (i * 50).ms)
                              .fadeIn(duration: 350.ms)
                              .slideY(
                                  begin: 0.08,
                                  duration: 350.ms,
                                  curve: Curves.easeOutQuad);
                        },
                      ),
                    );
                  },
                ),
            ],
          );
        },
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
            child: const Icon(Icons.analytics_outlined,
                size: 44, color: Color(0x6600466C)),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: -6, end: 6, duration: 2.seconds),
          const SizedBox(height: 20),
          Text('Belum ada data murid',
                  style: GuruTheme.titleLarge(color: const Color(0xFF6B6B80)))
              .animate()
              .fadeIn(delay: 200.ms),
          const SizedBox(height: 8),
          Text('Tambahkan murid di tab Murid\nlalu berikan tugas membaca.',
                  textAlign: TextAlign.center,
                  style: GuruTheme.bodyMedium())
              .animate()
              .fadeIn(delay: 300.ms),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header: judul + subtitle + search bar
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int totalCount;
  final bool isLoading;
  final TextEditingController controller;
  final ValueChanged<String> onSearch;

  const _Header({
    required this.totalCount,
    required this.isLoading,
    required this.controller,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: GuruTheme.surfaceLowest,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rapor Murid', style: GuruTheme.headline()),
                  const SizedBox(height: 4),
                  Text(
                    isLoading ? 'Memuat...' : '$totalCount murid terdaftar',
                    style: GuruTheme.bodyMedium(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: TextField(
                controller: controller,
                onChanged: onSearch,
                style: GuruTheme.bodyMedium(color: GuruTheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Cari nama murid...',
                  hintStyle: GuruTheme.bodyMedium(),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: GuruTheme.outline, size: 20),
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
            Container(height: 3, color: GuruTheme.primary),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Report Card
// ─────────────────────────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final String name;
  final String grade;
  final String dyslexia;
  final VoidCallback onTap;

  const _ReportCard({
    required this.name,
    required this.grade,
    required this.dyslexia,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color avatarBg = GuruTheme.avatarColor(name);

    return Container(
      decoration: GuruTheme.cardDecoration,
      child: Material(
        color: Colors.transparent,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          splashColor: const Color(0x0800466C),
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 24,
                  backgroundColor: avatarBg,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GuruTheme.titleMedium(),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(Icons.school_rounded,
                              size: 12, color: GuruTheme.outline),
                          const SizedBox(width: 4),
                          Text(grade, style: GuruTheme.bodySmall()),
                          const SizedBox(width: 12),
                          // "Lihat Rapor" chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: GuruTheme.successGreenBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Lihat Rapor',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: GuruTheme.successGreen,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (dyslexia.isNotEmpty && dyslexia != '-') ...[
                        const SizedBox(height: 4),
                        Text(dyslexia, style: GuruTheme.bodySmall()),
                      ],
                    ],
                  ),
                ),

                // Arrow
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: GuruTheme.primaryFixed,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_forward_rounded,
                      size: 15, color: GuruTheme.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}