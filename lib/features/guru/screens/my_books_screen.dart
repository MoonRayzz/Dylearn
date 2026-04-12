// ignore_for_file: deprecated_member_use, use_build_context_synchronously, unnecessary_underscores

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../config/guru_theme.dart';
import '../../../core/utils/responsive_helper.dart';
import 'add_book_screen.dart';

const String _kPending = 'pending';
const String _kLive = 'live';
const String _kRejected = 'rejected';

class MyBooksScreen extends StatefulWidget {
  const MyBooksScreen({super.key});

  @override
  State<MyBooksScreen> createState() => _MyBooksScreenState();
}

class _MyBooksScreenState extends State<MyBooksScreen>
    with SingleTickerProviderStateMixin {
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  late final TabController _tabController;

  // 3 tab sesuai design: Menunggu / Live / Ditolak
  static const _tabStatuses = [_kPending, _kLive, _kRejected];
  static const _tabLabels = ['Menunggu', 'Live', 'Ditolak'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabStatuses.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _streamForTab(int index) {
    if (_currentUser == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('library_books')
        .where('uploadBy', isEqualTo: _currentUser.uid)
        .where('status', isEqualTo: _tabStatuses[index])
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _deleteBook(String docId, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
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
                  Icons.delete_rounded,
                  color: GuruTheme.errorRed,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text('Hapus Buku?', style: GuruTheme.titleLarge()),
              const SizedBox(height: 8),
              Text(
                '"$title" akan dihapus dari antrian.\nTindakan ini tidak dapat dibatalkan.',
                textAlign: TextAlign.center,
                style: GuruTheme.bodyMedium(),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
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
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GuruTheme.errorRed,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Hapus',
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

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('library_books')
          .doc(docId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Buku berhasil dihapus.'),
            backgroundColor: GuruTheme.successGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menghapus: $e'),
            backgroundColor: GuruTheme.errorRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    if (_currentUser == null) {
      return const Center(child: Text('Sesi tidak valid.'));
    }

    return Scaffold(
      backgroundColor: GuruTheme.surfaceLow,
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          // Pill tab selector
          _TabSelector(controller: _tabController, uid: _currentUser.uid),
          const SizedBox(height: 8),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: List.generate(
                _tabStatuses.length,
                (i) => _BookListTab(
                  stream: _streamForTab(i),
                  statusIndex: i,
                  onDelete: _deleteBook,
                  r: r,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        color: GuruTheme.surfaceLowest,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text('Perpustakaan Saya', style: GuruTheme.titleLarge()),
                      const Spacer(),
                      // Upload button
                      TextButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AddBookScreen(),
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
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(
                          'Upload',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(height: 3, color: GuruTheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pill tab selector dengan realtime badge count
// ─────────────────────────────────────────────────────────────────────────────

class _TabSelector extends StatelessWidget {
  final TabController controller;
  final String uid;

  static const _dotColors = [
    GuruTheme.warningAmber,
    GuruTheme.successGreen,
    GuruTheme.errorRed,
  ];

  static const _tabStatuses = [_kPending, _kLive, _kRejected];
  static const _tabLabels = ['Menunggu', 'Live', 'Ditolak'];

  const _TabSelector({required this.controller, required this.uid});

  @override
  Widget build(BuildContext context) {
    // Gunakan stream untuk dapat badge count realtime
    return StreamBuilder<List<QuerySnapshot>>(
      stream: Stream.fromFuture(
        Future.wait(
          _tabStatuses.map(
            (s) => FirebaseFirestore.instance
                .collection('library_books')
                .where('uploadBy', isEqualTo: uid)
                .where('status', isEqualTo: s)
                .get(),
          ),
        ),
      ),
      builder: (context, snapshot) {
        final counts = snapshot.data != null
            ? snapshot.data!.map((q) => q.docs.length).toList()
            : [0, 0, 0];

        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return Container(
              margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: GuruTheme.surfaceMid,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: List.generate(_tabLabels.length, (i) {
                  final active = controller.index == i;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => controller.animateTo(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: active
                              ? GuruTheme.surfaceLowest
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: active ? GuruTheme.cardShadow : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _dotColors[i],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            // PERBAIKAN: Dibungkus dengan Flexible untuk mencegah overflow
                            Flexible(
                              child: Text(
                                _tabLabels[i],
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: active
                                      ? GuruTheme.primary
                                      : GuruTheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (counts[i] > 0) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: active
                                      ? GuruTheme.primary.withOpacity(0.12)
                                      : GuruTheme.surfaceHigh,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${counts[i]}',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: active
                                        ? GuruTheme.primary
                                        : GuruTheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// List buku per tab
// ─────────────────────────────────────────────────────────────────────────────

class _BookListTab extends StatelessWidget {
  final Stream<QuerySnapshot> stream;
  final int statusIndex;
  final Future<void> Function(String, String) onDelete;
  final ResponsiveHelper r;

  const _BookListTab({
    required this.stream,
    required this.statusIndex,
    required this.onDelete,
    required this.r,
  });

  static const _emptyIcons = [
    Icons.hourglass_empty_rounded,
    Icons.check_circle_outline_rounded,
    Icons.highlight_off_rounded,
  ];

  static const _emptyTitles = [
    'Tidak Ada Antrian',
    'Belum Ada Buku Live',
    'Tidak Ada Penolakan',
  ];

  static const _emptySubs = [
    'Semua buku sudah diproses\natau belum ada yang diupload.',
    'Buku yang lolos voting juri\nakan muncul di sini.',
    'Buku yang tidak lolos penilaian\nakan muncul di sini.',
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
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

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return _buildEmpty();

        return ListView.separated(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            MediaQuery.of(context).padding.bottom + 64 + 20 + 16,
          ),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            return _BookCard(
                  docId: docs[i].id,
                  data: data,
                  statusIndex: statusIndex,
                  onDelete: onDelete,
                  r: r,
                )
                .animate(delay: (i * 50).ms)
                .fadeIn(duration: 350.ms)
                .slideY(
                  begin: 0.08,
                  duration: 350.ms,
                  curve: Curves.easeOutQuad,
                );
          },
        );
      },
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: Color(0x0F00466C),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _emptyIcons[statusIndex],
                  size: 42,
                  color: const Color(0x6600466C),
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: -6, end: 6, duration: 2.seconds),
          const SizedBox(height: 20),
          Text(
            _emptyTitles[statusIndex],
            style: GuruTheme.titleLarge(color: const Color(0xFF6B6B80)),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 8),
          Text(
            _emptySubs[statusIndex],
            textAlign: TextAlign.center,
            style: GuruTheme.bodyMedium(),
          ).animate().fadeIn(delay: 300.ms),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Book card
// ─────────────────────────────────────────────────────────────────────────────

class _BookCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final int statusIndex; // 0=pending, 1=live, 2=rejected
  final Future<void> Function(String, String) onDelete;
  final ResponsiveHelper r;

  // Warna per status
  static const _statusColors = [
    GuruTheme.warningAmber,
    GuruTheme.successGreen,
    GuruTheme.errorRed,
  ];
  static const _statusBgs = [
    GuruTheme.warningAmberBg,
    GuruTheme.successGreenBg,
    GuruTheme.errorRedBg,
  ];
  static const _statusIcons = [
    Icons.hourglass_top_rounded,
    Icons.check_circle_rounded,
    Icons.cancel_rounded,
  ];
  static const _statusLabels = ['Menunggu', 'Live', 'Ditolak'];

  const _BookCard({
    required this.docId,
    required this.data,
    required this.statusIndex,
    required this.onDelete,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    final String title = data['title'] ?? 'Tanpa Judul';
    final String author = data['author'] ?? 'Anonim';
    final String cover = data['coverUrl'] ?? '';
    final String category = data['category'] ?? '';
    final int voteCount = (data['voteCount'] as num?)?.toInt() ?? 0;
    final int reqVotes = (data['requiredVotes'] as num?)?.toInt() ?? 3;
    final bool isPending = statusIndex == 0;

    return Container(
      decoration: GuruTheme.cardDecoration,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: cover.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: cover,
                      width: 60,
                      height: 80,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _CoverPlaceholder(r: r),
                      errorWidget: (_, __, ___) => _CoverPlaceholder(r: r),
                    )
                  : _CoverPlaceholder(r: r),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _statusBgs[statusIndex],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _statusIcons[statusIndex],
                              size: 11,
                              color: _statusColors[statusIndex],
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _statusLabels[statusIndex].toUpperCase(),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: _statusColors[statusIndex],
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Hapus hanya jika pending
                      if (isPending)
                        GestureDetector(
                          onTap: () => onDelete(docId, title),
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: const BoxDecoration(
                              color: GuruTheme.errorRedBg,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              color: GuruTheme.errorRed,
                              size: 16,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GuruTheme.titleMedium(),
                  ),
                  const SizedBox(height: 2),
                  Text('Oleh: $author', style: GuruTheme.bodySmall()),

                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (category.isNotEmpty)
                        _Chip(
                          label: category,
                          color: GuruTheme.primary,
                          bg: GuruTheme.primaryFixed,
                        ),
                    ],
                  ),

                  // Voting progress hanya untuk pending
                  if (isPending && reqVotes > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: voteCount / reqVotes,
                              minHeight: 5,
                              backgroundColor: GuruTheme.warningAmberBg,
                              valueColor: const AlwaysStoppedAnimation(
                                GuruTheme.warningAmber,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$voteCount/$reqVotes juri',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: GuruTheme.warningAmber,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  final ResponsiveHelper r;
  const _CoverPlaceholder({required this.r});

  @override
  Widget build(BuildContext context) => Container(
    width: 60,
    height: 80,
    color: GuruTheme.primaryFixed,
    child: const Icon(
      Icons.auto_stories_rounded,
      size: 26,
      color: GuruTheme.primary,
    ),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _Chip({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
  );
}
