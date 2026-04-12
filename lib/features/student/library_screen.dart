// ignore_for_file: deprecated_member_use, use_build_context_synchronously, unused_element, curly_braces_in_flow_control_structures, unused_local_variable, unnecessary_import, unnecessary_cast

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lottie/lottie.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:showcaseview/showcaseview.dart';
import '../../core/services/tutorial_service.dart';
import '../../shared/widgets/background_wrapper.dart';
import '../read_screen.dart';
import 'vote_list_screen.dart';
import '../../core/services/vote_service.dart';
import '../../shared/widgets/system_popup.dart';
import '../../core/utils/responsive_helper.dart';

// ════════════════════════════════════════════════════════════════
// TOP-LEVEL PRE-COMPILED REGEX
// ════════════════════════════════════════════════════════════════

final RegExp _reSentenceSplitter = RegExp(r'[.!?]+');
final RegExp _reNonAlphaSpace = RegExp(r'[^\w\s]+');

// FIX: pre-compute sekali — menggantikan const Color(0xFFF8F9FA).withOpacity(0.95) di dalam build()
final Color _searchBarBgColor = const Color(0xFFF8F9FA).withOpacity(0.95);

// ════════════════════════════════════════════════════════════════
// PERSISTENT PALETTE CACHE
// ════════════════════════════════════════════════════════════════

// FIX: pre-compile sebagai top-level static — tidak buat RegExp baru setiap _paletteKey() dipanggil
final RegExp _rePaletteKey = RegExp(r'[^a-zA-Z0-9]');

String _paletteKey(String imageUrl) {
  final cleaned = imageUrl.replaceAll(_rePaletteKey, '');
  final suffix = cleaned.length > 60
      ? cleaned.substring(cleaned.length - 60)
      : cleaned;
  return 'palette_color_$suffix';
}

Future<void> _savePaletteColor(String imageUrl, Color color) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_paletteKey(imageUrl), color.value);
  } catch (_) {}
}

Future<Color?> _loadPaletteColor(String imageUrl) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_paletteKey(imageUrl));
    if (value != null) return Color(value);
  } catch (_) {}
  return null;
}

Future<Color> _extractDominantColorIsolate(String imageUrl) async {
  try {
    final cached = await _loadPaletteColor(imageUrl);
    if (cached != null) return cached;

    Uint8List? imageBytes;
    if (imageUrl.startsWith('http')) {
      final response = await http
          .get(Uri.parse(imageUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        imageBytes = response.bodyBytes;
      }
    } else if (imageUrl.startsWith('data:image')) {
      imageBytes = base64Decode(imageUrl.split(',').last);
    }

    if (imageBytes == null) return const Color(0xFFFFFBE6);

    final palette = await PaletteGenerator.fromImageProvider(
      MemoryImage(imageBytes),
      size: const Size(50, 50),
      maximumColorCount: 3,
    );

    final color = palette.dominantColor?.color ??
        palette.vibrantColor?.color ??
        const Color(0xFFFFFBE6);

    await _savePaletteColor(imageUrl, color);
    return color;
  } catch (_) {
    return const Color(0xFFFFFBE6);
  }
}

// ════════════════════════════════════════════════════════════════
// LIBRARY SCREEN
// ════════════════════════════════════════════════════════════════

class LibraryScreen extends StatefulWidget {
  final String? activeStudentUid;
  final String? activeStudentName;

  const LibraryScreen({
    super.key,
    this.activeStudentUid,
    this.activeStudentName,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

// FIX 1: AutomaticKeepAliveClientMixin agar state tersimpan saat pindah Tab
class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {

  @override
  bool get wantKeepAlive => true;

  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier('');
  final ValueNotifier<String> _categoryNotifier = ValueNotifier('Semua');
  final ValueNotifier<String> _sibiNotifier = ValueNotifier('Semua Level');
  final ValueNotifier<bool> _isSpotlightViewNotifier = ValueNotifier(true);

  final Map<String, Color> _colorCache = {};
  final ValueNotifier<Color> _bgColorNotifier =
      ValueNotifier(const Color(0xFFFFFBE6));

  Timer? _colorDebounce;
  String _lastExtractedUrl = '';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final VoteService _voteService = VoteService();
  final TextEditingController _searchController = TextEditingController();
  bool _isTutorialChecked = false;

  final GlobalKey _juriKey = GlobalKey();
  // ── PERUBAHAN: _uploadKey dihapus ──────────────────────────────────────────
  // Tombol Upload buku publik dihapus dari tampilan siswa.
  // Guru menggunakan FAB di GuruHomeScreen untuk upload ke library publik.
  final GlobalKey _lastReadKey = GlobalKey();
  final GlobalKey _searchFilterKey = GlobalKey();
  final GlobalKey _bookListKey = GlobalKey();

  late final Map<GlobalKey, String> _showcaseDescriptions;

  late Stream<QuerySnapshot> _liveBooksStream;
  Stream<QuerySnapshot>? _lastReadStream;

  String get _targetUid => widget.activeStudentUid ?? _auth.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _initStreams();

    // ── PERUBAHAN: Hapus _uploadKey dari descriptions dan showcase ───────────
    _showcaseDescriptions = {
      _juriKey:
          'Cek tugas Juri Cilik di sini! Nilai buku kiriman agar bisa masuk perpustakaan.',
      _lastReadKey:
          'Tiket Emas ini akan membawamu kembali ke cerita yang belum selesai dibaca.',
      _searchFilterKey:
          'Gunakan kapsul ajaib ini untuk mencari cerita yang kamu mau!',
      _bookListKey:
          'Geser ke kanan atau kiri untuk memilih petualanganmu selanjutnya!',
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndSeedInitialBooks();
    });
  }

  @override
  void dispose() {
    _colorDebounce?.cancel();
    _searchController.dispose();
    _bgColorNotifier.dispose();
    _searchQueryNotifier.dispose();
    _categoryNotifier.dispose();
    _sibiNotifier.dispose();
    _isSpotlightViewNotifier.dispose();
    super.dispose();
  }

  void _initStreams() {
    _liveBooksStream = FirebaseFirestore.instance
        .collection('library_books')
        .where('status', isEqualTo: 'live')
        .orderBy('createdAt', descending: true)
        .snapshots();

    final user = _auth.currentUser;
    if (user != null) {
      Query query = FirebaseFirestore.instance
          .collection('users')
          .doc(_targetUid)
          .collection('my_library');

      if (widget.activeStudentUid != null) {
        query = query.where('createdBy', isEqualTo: user.uid);
      }

      _lastReadStream = query
          .orderBy('lastAccessed', descending: true)
          .limit(5)
          .snapshots();
    }
  }

  void _scheduleColorUpdate(String imageUrl) {
    if (!_isSpotlightViewNotifier.value) return;
    if (imageUrl.isEmpty || imageUrl == _lastExtractedUrl) return;

    if (_colorCache.containsKey(imageUrl)) {
      _bgColorNotifier.value = _colorCache[imageUrl]!;
      _lastExtractedUrl = imageUrl;
      return;
    }

    _loadPaletteColor(imageUrl).then((diskColor) {
      if (!mounted) return;
      if (diskColor != null) {
        _colorCache[imageUrl] = diskColor;
        _bgColorNotifier.value = diskColor;
        _lastExtractedUrl = imageUrl;
        return;
      }

      _colorDebounce?.cancel();
      _colorDebounce = Timer(
        const Duration(milliseconds: 400),
        () async {
          final color = await _extractDominantColorIsolate(imageUrl);
          if (!mounted) return;
          _colorCache[imageUrl] = color;
          _bgColorNotifier.value = color;
          _lastExtractedUrl = imageUrl;
        },
      );
    });
  }

  Future<void> _checkAndShowTutorial(BuildContext showcaseContext) async {
    if (widget.activeStudentUid != null) return;

    final bool hasSeen = await TutorialService.hasSeenTutorial('library');
    if (!hasSeen && mounted) {
      // ── PERUBAHAN: Hapus _uploadKey dari showcase ────────────────────────
      ShowCaseWidget.of(showcaseContext).startShowCase([
        _juriKey,
        _lastReadKey,
        _searchFilterKey,
        _bookListKey,
      ]);
      await TutorialService.markTutorialAsSeen('library');
    }
  }

  Future<void> _checkAndSeedInitialBooks() async {
    await FirebaseFirestore.instance
        .collection('library_books')
        .where('status', isEqualTo: 'live')
        .limit(1)
        .get();
  }

  Future<void> _openBookSmart(
    BuildContext context,
    String rawDocId,
    Map<String, dynamic> bookData,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final String fullBookId = 'lib_$rawDocId';
    int startIndex = 0;

    try {
      final docSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_targetUid)
          .collection('my_library')
          .doc(fullBookId)
          .get(const GetOptions(source: Source.cache));

      if (docSnap.exists) {
        // FIX: DocumentSnapshot.data() nullable — null check sebelum cast
        final raw = docSnap.data();
        if (raw != null) {
          startIndex = (raw as Map<String, dynamic>)['lastSentenceIndex'] ?? 0;
        }
      }

      _updateLastReadMetadata(fullBookId, bookData);

      List<String> pages = [];
      if (bookData['imageUrls'] != null &&
          (bookData['imageUrls'] as List).isNotEmpty) {
        pages = List<String>.from(bookData['imageUrls']);
      } else {
        final String coverUrl =
            bookData['coverUrl'] ?? bookData['imageUrl'] ?? '';
        if (coverUrl.isNotEmpty) pages = [coverUrl];
      }

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReadScreen(
            text: bookData['content'] ?? '',
            documentId: fullBookId,
            initialIndex: startIndex,
            imageUrls: pages,
            activeStudentUid: widget.activeStudentUid,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Gagal load dari cache, fallback ke pembukaan instan: $e');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReadScreen(
            text: bookData['content'] ?? '',
            documentId: fullBookId,
            activeStudentUid: widget.activeStudentUid,
          ),
        ),
      );
    }
  }

  Future<void> _updateLastReadMetadata(
    String fullBookId,
    Map<String, dynamic> bookData,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final existingDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_targetUid)
        .collection('my_library')
        .doc(fullBookId)
        .get();

    String existingCreatedBy = '';
    if (existingDoc.exists) {
      existingCreatedBy = existingDoc.data()?['createdBy'] ?? '';
    }

    final dataToSave = {
      'bookId': fullBookId,
      'title': bookData['title'] ?? 'Tanpa Judul',
      'author': bookData['author'] ?? 'Anonim',
      'category': bookData['category'] ?? 'Umum',
      'sibiLevel': bookData['sibiLevel'] ?? 'Belum Tahu 🤷‍♂️',
      'coverUrl': bookData['coverUrl'] ?? '',
      'imageUrl': bookData['coverUrl'] ?? '',
      'imageUrls': bookData['imageUrls'] ?? [],
      'ocrText': bookData['content'] ?? '',
      'content': bookData['content'] ?? '',
      'fileType': 'library_book',
      'wordCount': bookData['wordCount'] ?? 0,
      'createdBy': existingCreatedBy,
      'totalSentences': (bookData['content'] ?? '')
          .toString()
          .split(_reSentenceSplitter)
          .length,
      'lastAccessed': FieldValue.serverTimestamp(),
    };
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_targetUid)
        .collection('my_library')
        .doc(fullBookId)
        .set(dataToSave, SetOptions(merge: true));
  }

  Future<void> _deleteHistoryItem(String docId, String title) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_targetUid)
          .collection('my_library')
          .doc(docId)
          .delete();
      if (mounted) {
        showSystemPopup(
          context: context,
          type: PopupType.success,
          title: 'Selesai Dirapikan',
          message: "Cerita '$title' sudah dirapikan dari daftarmu ya.",
          confirmText: 'Oke',
        );
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _showDeleteConfirmDialog(String docId, String title) {
    showSystemPopup(
      context: context,
      type: PopupType.confirm,
      title: 'Hapus Buku?',
      message: "Apa kamu ingin merapikan cerita '$title' dari daftar bacamu?",
      confirmText: 'Ya, Hapus',
      cancelText: 'Kembali',
      onConfirm: () => _deleteHistoryItem(docId, title),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = context.r;

    final TextStyle tooltipStyle = TextStyle(
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
      fontSize: r.font(14),
      color: Colors.black87,
    );

    return ShowCaseWidget(
      onStart: (index, key) {
        final text = _showcaseDescriptions[key];
        if (text != null) TutorialService.speakShowcaseText(text);
      },
      onComplete: (index, key) => TutorialService.stopSpeaking(),
      onFinish: () => TutorialService.stopSpeaking(),
      builder: (showcaseContext) {
        if (!_isTutorialChecked) {
          _isTutorialChecked = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkAndShowTutorial(showcaseContext);
          });
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF8F9FA),
          body: _AnimatedBackground(
            bgColorNotifier: _bgColorNotifier,
            isSpotlightNotifier: _isSpotlightViewNotifier,
            child: SafeArea(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: LibraryHeaderWidget(
                      voteService: _voteService,
                      auth: _auth,
                      juriKey: _juriKey,
                      showcaseDescriptions: _showcaseDescriptions,
                      tooltipStyle: tooltipStyle,
                      r: r,
                      activeStudentName: widget.activeStudentName,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Showcase(
                      key: _lastReadKey,
                      description: _showcaseDescriptions[_lastReadKey]!,
                      descTextStyle: tooltipStyle,
                      child: LastReadSectionWidget(
                        lastReadStream: _lastReadStream,
                        onOpenBook: _openBookSmart,
                        onDeleteConfirm: _showDeleteConfirmDialog,
                        r: r,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Container(
                      // FIX: static final — tidak alokasikan Color baru setiap build()
                      color: _searchBarBgColor,
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Showcase(
                        key: _searchFilterKey,
                        description: _showcaseDescriptions[_searchFilterKey]!,
                        descTextStyle: tooltipStyle,
                        child: SearchBarWidget(
                          searchController: _searchController,
                          searchQueryNotifier: _searchQueryNotifier,
                          isSpotlightViewNotifier: _isSpotlightViewNotifier,
                          r: r,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: EmojiFiltersWidget(
                      liveBooksStream: _liveBooksStream,
                      categoryNotifier: _categoryNotifier,
                      sibiNotifier: _sibiNotifier,
                      r: r,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Showcase(
                      key: _bookListKey,
                      description: _showcaseDescriptions[_bookListKey]!,
                      descTextStyle: tooltipStyle,
                      child: MainStageWidget(
                        liveBooksStream: _liveBooksStream,
                        searchQueryNotifier: _searchQueryNotifier,
                        categoryNotifier: _categoryNotifier,
                        sibiNotifier: _sibiNotifier,
                        viewNotifier: _isSpotlightViewNotifier,
                        onColorUpdate: _scheduleColorUpdate,
                        onOpenBook: _openBookSmart,
                        r: r,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(height: r.size(120)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedBackground extends StatelessWidget {
  final ValueNotifier<Color> bgColorNotifier;
  final ValueNotifier<bool> isSpotlightNotifier;
  final Widget child;

  static const Color _defaultBg = Color(0xFFF8F9FA);
  static const Color _defaultGradientEnd = Color(0xFFFFFBE6);

  const _AnimatedBackground({
    required this.bgColorNotifier,
    required this.isSpotlightNotifier,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpotlightNotifier,
      child: child,
      builder: (context, isSpotlight, staticChild) {
        return Stack(
          children: [
            Positioned.fill(
              child: isSpotlight
                  ? ValueListenableBuilder<Color>(
                      valueListenable: bgColorNotifier,
                      builder: (context, bgColor, _) {
                        return TweenAnimationBuilder<Color?>(
                          tween: ColorTween(end: bgColor),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOut,
                          builder: (context, animColor, _) {
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    _defaultBg,
                                    (animColor ?? _defaultGradientEnd)
                                        .withOpacity(0.4),
                                  ],
                                  stops: const [0.3, 1.0],
                                ),
                              ),
                              child: const SizedBox.expand(),
                            );
                          },
                        );
                      },
                    )
                  : const DecoratedBox(
                      decoration: BoxDecoration(color: _defaultBg),
                      child: SizedBox.expand(),
                    ),
            ),
            staticChild!,
          ],
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════
// LIBRARY HEADER WIDGET
// ── PERUBAHAN: Upload button dihapus. Hanya Juri Cilik yang tampil.
// Siswa tidak bisa upload ke library publik. Guru upload via GuruHomeScreen FAB.
// ════════════════════════════════════════════════════════════════
class LibraryHeaderWidget extends StatelessWidget {
  final VoteService voteService;
  final FirebaseAuth auth;
  final GlobalKey juriKey;
  // ── PERUBAHAN: uploadKey parameter dihapus ─────────────────────────────
  final Map<GlobalKey, String> showcaseDescriptions;
  final TextStyle tooltipStyle;
  final ResponsiveHelper r;
  final String? activeStudentName;

  static final TextStyle _titleBase = GoogleFonts.comicNeue(
    fontWeight: FontWeight.w900,
    height: 1.1,
  );

  static final Color _blueColor = Colors.blue.shade800;
  static final Color _blueColorLight = Colors.blue.shade300;

  const LibraryHeaderWidget({
    super.key,
    required this.voteService,
    required this.auth,
    required this.juriKey,
    required this.showcaseDescriptions,
    required this.tooltipStyle,
    required this.r,
    this.activeStudentName,
  });

  @override
  Widget build(BuildContext context) {
    final bool isTeacherMode = activeStudentName != null;

    final String shortName = isTeacherMode
      ? activeStudentName!.split(' ').first
      : '';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        r.spacing(20),
        r.spacing(20),
        r.spacing(20),
        r.spacing(15),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (isTeacherMode)
                Padding(
                  padding: EdgeInsets.only(right: r.spacing(12)),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
                    ),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: _blueColor),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),

              Text(
                isTeacherMode ? 'Pilih Buku\nUntuk $shortName' : 'Pustaka\nCerita',
                style: _titleBase.copyWith(
                  fontSize: r.font(isTeacherMode ? 22 : 26),
                  color: _blueColor,
                ),
              ),
              if (!isTeacherMode) ...[
                SizedBox(width: r.spacing(8)),
                SizedBox(
                  height: r.size(50),
                  width: r.size(50),
                  child: RepaintBoundary(
                    child: Lottie.asset(
                      'assets/animations/BOOK.json',
                      fit: BoxFit.contain,
                      errorBuilder: (c, e, s) => Icon(
                        Icons.menu_book_rounded,
                        color: _blueColorLight,
                        size: r.size(40),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),

          // ── PERUBAHAN: Tampilkan hanya tombol Juri Cilik untuk siswa ────────
          // Tombol Upload (AddBookScreen) DIHAPUS dari tampilan siswa.
          // - isTeacherMode = true  → guru mode, kedua tombol disembunyikan
          // - isTeacherMode = false → mode siswa, hanya tampil Juri Cilik
          if (!isTeacherMode)
            StreamBuilder<int>(
              stream: voteService.getPendingVotesCountStream(
                auth.currentUser?.uid ?? '',
              ),
              builder: (context, snapshot) {
                final int count = snapshot.data ?? 0;
                return Showcase(
                  key: juriKey,
                  description: showcaseDescriptions[juriKey]!,
                  descTextStyle: tooltipStyle,
                  child: _ChunkyButton(
                    icon: Icons.emoji_events_rounded,
                    color: Colors.amber.shade400,
                    badgeCount: count,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VoteListScreen(),
                      ),
                    ),
                    r: r,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class LastReadSectionWidget extends StatelessWidget {
  final Stream<QuerySnapshot>? lastReadStream;
  final Function(BuildContext, String, Map<String, dynamic>) onOpenBook;
  final Function(String, String) onDeleteConfirm;
  final ResponsiveHelper r;

  const LastReadSectionWidget({
    super.key,
    required this.lastReadStream,
    required this.onOpenBook,
    required this.onDeleteConfirm,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    if (lastReadStream == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: lastReadStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final validDocs = snapshot.data!.docs
            .where((doc) =>
                (doc.data() as Map)['fileType'] == 'library_book')
            .toList();

        if (validDocs.isEmpty) return const SizedBox.shrink();

        return SizedBox(
          height: r.size(100),
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: r.spacing(20)),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: validDocs.length,
            itemBuilder: (context, index) {
              final doc = validDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              return Padding(
                padding: EdgeInsets.only(right: r.spacing(16)),
                child: _MiniGoldenTicketCard(
                  data: data,
                  onTap: () => onOpenBook(
                    context,
                    doc.id.replaceAll('lib_', ''),
                    data,
                  ),
                  onLongPress: () =>
                      onDeleteConfirm(doc.id, data['title'] ?? ''),
                  r: r,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class SearchBarWidget extends StatelessWidget {
  final TextEditingController searchController;
  final ValueNotifier<String> searchQueryNotifier;
  final ValueNotifier<bool> isSpotlightViewNotifier;
  final ResponsiveHelper r;

  static final Color _shadowColor = Colors.black.withOpacity(0.05);

  const SearchBarWidget({
    super.key,
    required this.searchController,
    required this.searchQueryNotifier,
    required this.isSpotlightViewNotifier,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: r.spacing(20),
        vertical: r.spacing(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: _shadowColor,
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade200, width: 2),
              ),
              child: ValueListenableBuilder<String>(
                valueListenable: searchQueryNotifier,
                builder: (context, query, _) {
                  return TextField(
                    controller: searchController,
                    style: TextStyle(
                      fontFamily: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.fontFamily,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Cari naga atau putri? 🔍',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: Colors.blue[600],
                        size: r.size(28),
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: r.spacing(20),
                        vertical: r.spacing(16),
                      ),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.cancel_rounded,
                                color: Colors.grey,
                              ),
                              onPressed: () {
                                searchController.clear();
                                searchQueryNotifier.value = '';
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) =>
                        searchQueryNotifier.value = value.toLowerCase(),
                  );
                },
              ),
            ),
          ),
          SizedBox(width: r.spacing(12)),
          ValueListenableBuilder<bool>(
            valueListenable: isSpotlightViewNotifier,
            builder: (context, isSpotlight, _) {
              final Color toggleShadow =
                  (isSpotlight ? Colors.orange : Colors.blue).withOpacity(0.3);

              return GestureDetector(
                onTap: () =>
                    isSpotlightViewNotifier.value = !isSpotlightViewNotifier.value,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: r.size(55),
                  width: r.size(55),
                  decoration: BoxDecoration(
                    color: isSpotlight
                        ? Colors.orange.shade400
                        : Colors.blue.shade400,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: toggleShadow,
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    isSpotlight
                        ? Icons.grid_view_rounded
                        : Icons.view_carousel_rounded,
                    color: Colors.white,
                    size: r.size(28),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class EmojiFiltersWidget extends StatelessWidget {
  final Stream<QuerySnapshot> liveBooksStream;
  final ValueNotifier<String> categoryNotifier;
  final ValueNotifier<String> sibiNotifier;
  final ResponsiveHelper r;

  static const List<Map<String, String>> _emojiCategories = [
    {'title': 'Semua', 'emoji': '📚'},
    {'title': 'Dongeng', 'emoji': '🧚‍♀️'},
    {'title': 'Legenda', 'emoji': '🐉'},
    {'title': 'Cerpen', 'emoji': '📖'},
    {'title': 'Cerita Rakyat', 'emoji': '🛖'},
    {'title': 'Mitos', 'emoji': '👑'},
  ];

  static const List<Map<String, String>> _emojiSibiLevels = [
    {'title': 'Semua Level', 'emoji': '🌟'},
    {'title': 'Bintang Kecil', 'emoji': '⭐'},
    {'title': 'Petualang Kata', 'emoji': '🎒'},
    {'title': 'Jagoan Baca', 'emoji': '🦸‍♂️'},
    {'title': 'Kapten Cerita', 'emoji': '⛵'},
    {'title': 'Master Buku', 'emoji': '👑'},
    {'title': 'Belum Tahu', 'emoji': '🤷‍♂️'},
  ];

  const EmojiFiltersWidget({
    super.key,
    required this.liveBooksStream,
    required this.categoryNotifier,
    required this.sibiNotifier,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: liveBooksStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final Set<String> availableCategories = {};
        final Set<String> availableSibiLevels = {};

        for (final doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          availableCategories
              .add((data['category'] ?? 'Dongeng').toString());
          final cleanSibi = (data['sibiLevel'] ?? 'Belum Tahu')
              .toString()
              .replaceAll(_reNonAlphaSpace, '')
              .trim();
          availableSibiLevels.add(cleanSibi);
        }

        final activeCategories = _emojiCategories.where((cat) {
          if (cat['title'] == 'Semua') return true;
          return availableCategories.contains(cat['title']);
        }).toList();

        final activeSibiLevels = _emojiSibiLevels.where((sibi) {
          if (sibi['title'] == 'Semua Level') return true;
          final filterSibiClean =
              sibi['title']!.replaceAll(_reNonAlphaSpace, '').trim();
          return availableSibiLevels
              .any((dbLevel) => dbLevel.contains(filterSibiClean));
        }).toList();

        return AnimatedBuilder(
          animation: Listenable.merge([categoryNotifier, sibiNotifier]),
          builder: (context, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (activeCategories.length > 1)
                  SizedBox(
                    height: r.size(40),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding:
                          EdgeInsets.symmetric(horizontal: r.spacing(20)),
                      itemCount: activeCategories.length,
                      itemBuilder: (context, index) {
                        final cat = activeCategories[index];
                        final isSelected = categoryNotifier.value ==
                            (cat['title'] == 'Semua'
                                ? 'Semua'
                                : cat['title']);
                        return _SleekFilterChip(
                          emoji: cat['emoji']!,
                          title: cat['title']!,
                          isSelected: isSelected,
                          onTap: () =>
                              categoryNotifier.value = cat['title']!,
                          r: r,
                        );
                      },
                    ),
                  ),
                if (activeCategories.length > 1)
                  SizedBox(height: r.spacing(10)),
                if (activeSibiLevels.length > 1)
                  SizedBox(
                    height: r.size(40),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      padding:
                          EdgeInsets.symmetric(horizontal: r.spacing(20)),
                      itemCount: activeSibiLevels.length,
                      itemBuilder: (context, index) {
                        final sibi = activeSibiLevels[index];
                        final isSelected = sibiNotifier.value ==
                            (sibi['title'] == 'Semua Level'
                                ? 'Semua Level'
                                : sibi['title']);
                        return _SleekFilterChip(
                          emoji: sibi['emoji']!,
                          title: sibi['title']!,
                          isSelected: isSelected,
                          onTap: () =>
                              sibiNotifier.value = sibi['title']!,
                          r: r,
                        );
                      },
                    ),
                  ),
                if (activeSibiLevels.length > 1)
                  SizedBox(height: r.spacing(20)),
              ],
            );
          },
        );
      },
    );
  }
}

class MainStageWidget extends StatelessWidget {
  final Stream<QuerySnapshot> liveBooksStream;
  final ValueNotifier<String> searchQueryNotifier;
  final ValueNotifier<String> categoryNotifier;
  final ValueNotifier<String> sibiNotifier;
  final ValueNotifier<bool> viewNotifier;
  final Function(String) onColorUpdate;
  final Function(BuildContext, String, Map<String, dynamic>) onOpenBook;
  final ResponsiveHelper r;

  const MainStageWidget({
    super.key,
    required this.liveBooksStream,
    required this.searchQueryNotifier,
    required this.categoryNotifier,
    required this.sibiNotifier,
    required this.viewNotifier,
    required this.onColorUpdate,
    required this.onOpenBook,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: liveBooksStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: r.size(300),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return SizedBox(
            height: r.size(300),
            child: Center(
              child: Text(
                'Belum ada cerita... 😢',
                style: TextStyle(fontSize: r.font(18)),
              ),
            ),
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            final toPreCache = snapshot.data!.docs.take(3);
            for (final doc in toPreCache) {
              final data = doc.data() as Map<String, dynamic>;
              final String url =
                  data['coverUrl'] ?? data['imageUrl'] ?? '';
              if (url.startsWith('http')) {
                precacheImage(CachedNetworkImageProvider(url), context);
              }
            }
          }
        });

        return AnimatedBuilder(
          animation: Listenable.merge([
            searchQueryNotifier,
            categoryNotifier,
            sibiNotifier,
          ]),
          builder: (context, _) {
            final filteredDocs = snapshot.data!.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final title =
                  (data['title'] ?? '').toString().toLowerCase();
              final category =
                  (data['category'] ?? 'Dongeng').toString();
              final sibiLevel =
                  (data['sibiLevel'] ?? 'Belum Tahu').toString();

              final matchesSearch = searchQueryNotifier.value.isEmpty ||
                  title.contains(searchQueryNotifier.value);
              final matchesCategory =
                  categoryNotifier.value == 'Semua' ||
                      category == categoryNotifier.value;

              final dbSibi =
                  sibiLevel.replaceAll(_reNonAlphaSpace, '').trim();
              final filterSibi = sibiNotifier.value
                  .replaceAll(_reNonAlphaSpace, '')
                  .trim();
              final matchesSibi = sibiNotifier.value == 'Semua Level' ||
                  dbSibi.contains(filterSibi);

              return matchesSearch && matchesCategory && matchesSibi;
            }).toList();

            if (filteredDocs.isEmpty) {
              return SizedBox(
                height: r.size(300),
                child: Center(
                  child: Text(
                    'Cerita tidak ditemukan 🔍',
                    style: TextStyle(fontSize: r.font(18)),
                  ),
                ),
              );
            }

            return ValueListenableBuilder<bool>(
              valueListenable: viewNotifier,
              builder: (context, isSpotlight, _) {
                if (isSpotlight) {
                  return SpotlightViewSection(
                    filteredDocs: filteredDocs,
                    onColorUpdate: onColorUpdate,
                    onOpenBook: onOpenBook,
                    r: r,
                  );
                } else {
                  return GridViewSection(
                    filteredDocs: filteredDocs,
                    onOpenBook: onOpenBook,
                    r: r,
                  );
                }
              },
            );
          },
        );
      },
    );
  }
}

class SpotlightViewSection extends StatefulWidget {
  final List<QueryDocumentSnapshot> filteredDocs;
  final Function(String) onColorUpdate;
  final Function(BuildContext, String, Map<String, dynamic>) onOpenBook;
  final ResponsiveHelper r;

  const SpotlightViewSection({
    super.key,
    required this.filteredDocs,
    required this.onColorUpdate,
    required this.onOpenBook,
    required this.r,
  });

  @override
  State<SpotlightViewSection> createState() => _SpotlightViewSectionState();
}

class _SpotlightViewSectionState extends State<SpotlightViewSection> {
  late PageController _spotlightController;
  int _currentSpotlightIndex = 0;

  @override
  void initState() {
    super.initState();
    _spotlightController = PageController(
      viewportFraction: 0.68,
      initialPage: 0,
      keepPage: true,
    );
    _notifyColorUpdate();
  }

  @override
  void didUpdateWidget(SpotlightViewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentSpotlightIndex >= widget.filteredDocs.length) {
      _currentSpotlightIndex = 0;
    }
    _notifyColorUpdate();
  }

  void _notifyColorUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.filteredDocs.isNotEmpty && mounted) {
        final data = widget.filteredDocs[_currentSpotlightIndex].data()
            as Map<String, dynamic>;
        widget.onColorUpdate(data['coverUrl'] ?? data['imageUrl'] ?? '');
      }
    });
  }

  @override
  void dispose() {
    _spotlightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.r.size(560),
      child: Stack(
        alignment: Alignment.center,
        children: [
          PageView.builder(
            controller: _spotlightController,
            allowImplicitScrolling: true,
            physics: const BouncingScrollPhysics(),
            itemCount: widget.filteredDocs.length,
            onPageChanged: (index) {
              setState(() => _currentSpotlightIndex = index);
              final data = widget.filteredDocs[index].data()
                  as Map<String, dynamic>;
              widget.onColorUpdate(
                  data['coverUrl'] ?? data['imageUrl'] ?? '');
            },
            itemBuilder: (context, index) {
              final doc = widget.filteredDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              return _SingleSpotlightItem(
                controller: _spotlightController,
                index: index,
                data: data,
                docId: doc.id,
                isActive: index == _currentSpotlightIndex,
                onTap: () => widget.onOpenBook(context, doc.id, data),
                r: widget.r,
              );
            },
          ),
          if (widget.filteredDocs.length > 1)
            Positioned(
              left: 10,
              child: IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_rounded,
                  color: Colors.white,
                  size: widget.r.size(40),
                ),
                onPressed: () {
                  if (_currentSpotlightIndex > 0) {
                    _spotlightController.previousPage(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                    );
                  }
                },
              ),
            ),
          if (widget.filteredDocs.length > 1)
            Positioned(
              right: 10,
              child: IconButton(
                icon: Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: widget.r.size(40),
                ),
                onPressed: () {
                  if (_currentSpotlightIndex <
                      widget.filteredDocs.length - 1) {
                    _spotlightController.nextPage(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                    );
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SingleSpotlightItem extends StatelessWidget {
  final PageController controller;
  final int index;
  final Map<String, dynamic> data;
  final String docId;
  final bool isActive;
  final VoidCallback onTap;
  final ResponsiveHelper r;

  const _SingleSpotlightItem({
    required this.controller,
    required this.index,
    required this.data,
    required this.docId,
    required this.isActive,
    required this.onTap,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: RepaintBoundary(
        child: _SpotlightCard(
          data: data,
          docId: docId,
          isActive: isActive,
          onTap: onTap,
          r: r,
        ),
      ),
      builder: (context, child) {
        double scale = 0.75;
        double opacity = 0.4;

        if (controller.hasClients && controller.position.haveDimensions) {
          final page = controller.page ?? index.toDouble();
          final delta = (page - index).abs();
          scale = (1 - (delta * 0.25)).clamp(0.75, 1.0);
          opacity = (1 - (delta * 0.6)).clamp(0.4, 1.0);
        } else if (isActive) {
          scale = 1.0;
          opacity = 1.0;
        }

        return Center(
          child: Transform.scale(
            scale: Curves.easeOut.transform(scale),
            child: Opacity(
              opacity: opacity,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class GridViewSection extends StatelessWidget {
  final List<QueryDocumentSnapshot> filteredDocs;
  final Function(BuildContext, String, Map<String, dynamic>) onOpenBook;
  final ResponsiveHelper r;

  static const SliverGridDelegateWithFixedCrossAxisCount _gridDelegate =
      SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    childAspectRatio: 0.70,
    crossAxisSpacing: 16,
    mainAxisSpacing: 20,
  );

  const GridViewSection({
    super.key,
    required this.filteredDocs,
    required this.onOpenBook,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.spacing(20)),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: _gridDelegate,
        itemCount: filteredDocs.length,
        itemBuilder: (context, index) {
          final doc = filteredDocs[index];
          return _PlayfulGridBookCard(
            data: doc.data() as Map<String, dynamic>,
            docId: doc.id,
            onTap: () => onOpenBook(
              context,
              doc.id,
              doc.data() as Map<String, dynamic>,
            ),
            r: r,
          );
        },
      ),
    );
  }
}

class _ChunkyButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int badgeCount;
  final VoidCallback onTap;
  final ResponsiveHelper r;

  static const TextStyle _badgeTextStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.bold,
  );

  const _ChunkyButton({
    required this.icon,
    required this.color,
    this.badgeCount = 0,
    required this.onTap,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    final Color shadowColor = color.withOpacity(0.5);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: r.size(50),
            width: r.size(50),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  offset: const Offset(0, 4),
                  blurRadius: 0,
                ),
              ],
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(icon, color: Colors.white, size: r.size(28)),
          ),
          if (badgeCount > 0)
            Positioned(
              top: -5,
              right: -5,
              child: Container(
                padding: EdgeInsets.all(r.spacing(6)),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black26, blurRadius: 4),
                  ],
                ),
                child: Text(
                  badgeCount.toString(),
                  style: _badgeTextStyle.copyWith(fontSize: r.font(12)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SleekFilterChip extends StatelessWidget {
  final String emoji;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;
  final ResponsiveHelper r;

  const _SleekFilterChip({
    required this.emoji,
    required this.title,
    required this.isSelected,
    required this.onTap,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgColor = isSelected
        ? Colors.orange.shade500
        : Colors.white.withOpacity(0.8);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: EdgeInsets.only(right: r.spacing(10)),
        padding: EdgeInsets.symmetric(
          horizontal: r.spacing(16),
          vertical: r.spacing(8),
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: TextStyle(fontSize: r.font(16))),
            SizedBox(width: r.spacing(6)),
            Text(
              title,
              style: TextStyle(
                fontFamily:
                    Theme.of(context).textTheme.bodyMedium?.fontFamily,
                fontSize: r.font(13),
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeacherBadge extends StatelessWidget {
  final ResponsiveHelper r;

  const _TeacherBadge({required this.r});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.spacing(8), vertical: r.spacing(4)),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.school_rounded, color: Colors.white, size: r.size(12)),
          SizedBox(width: r.spacing(4)),
          Text(
            "Tugas Guru",
            style: GoogleFonts.poppins(
              fontSize: r.font(9),
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniGoldenTicketCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ResponsiveHelper r;

  static final Color _shadowColor = Colors.orange.withOpacity(0.4);
  static final Color _borderColor = Colors.white.withOpacity(0.5);
  static final Color _progressBgColor = Colors.white.withOpacity(0.3);

  static const LinearGradient _gradient = LinearGradient(
    colors: [Color(0xFFFFD700), Color(0xFFFFB000)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const BorderRadius _cardRadius = BorderRadius.all(Radius.circular(20));
  static const BorderRadius _coverRadius = BorderRadius.all(Radius.circular(12));
  static const BorderRadius _progressRadius = BorderRadius.all(Radius.circular(10));

  static const BoxDecoration _playBtnDecoration = BoxDecoration(
    color: Colors.white,
    shape: BoxShape.circle,
  );

  static final TextStyle _lanjutkanStyle =
      GoogleFonts.comicNeue(fontWeight: FontWeight.w900);

  const _MiniGoldenTicketCard({
    required this.data,
    required this.onTap,
    required this.onLongPress,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    final String title = data['title'] ?? 'Lanjut Baca';
    final String coverUrl = data['coverUrl'] ?? data['imageUrl'] ?? '';
    final int lastIndex = data['lastSentenceIndex'] ?? 0;
    final int totalSentences = data['totalSentences'] ?? 1;
    final double progress = (lastIndex / totalSentences).clamp(0.0, 1.0);

    final bool isTeacherTask = data['createdBy'] != null && data['createdBy'].toString().isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: r.size(280),
        padding: EdgeInsets.all(r.spacing(10)),
        decoration: BoxDecoration(
          gradient: _gradient,
          borderRadius: _cardRadius,
          boxShadow: [
            BoxShadow(
              color: _shadowColor,
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
          border: Border.all(color: _borderColor, width: 2),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: _coverRadius,
              child: SizedBox(
                width: r.size(55),
                height: r.size(75),
                child: _CoverImage(
                  url: coverUrl,
                  title: title,
                  isSpotlight: false,
                ),
              ),
            ),
            SizedBox(width: r.spacing(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Text(
                        'Lanjutkan! 🚀',
                        style: _lanjutkanStyle.copyWith(
                          fontSize: r.font(13),
                          color: Colors.orange.shade900,
                        ),
                      ),
                      if (isTeacherTask) ...[
                        SizedBox(width: r.spacing(6)),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: r.spacing(6), vertical: r.spacing(2)),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "Tugas",
                            style: GoogleFonts.poppins(fontSize: r.font(8), fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: r.spacing(2)),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.fontFamily,
                      fontSize: r.font(14),
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: r.spacing(6)),
                  ClipRRect(
                    borderRadius: _progressRadius,
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: r.size(6),
                      backgroundColor: _progressBgColor,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: r.spacing(8)),
            Container(
              height: r.size(40),
              width: r.size(40),
              decoration: _playBtnDecoration,
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.orange,
                size: r.size(30),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final bool isActive;
  final VoidCallback onTap;
  final ResponsiveHelper r;

  static final Color _activeShadow = Colors.black.withOpacity(0.3);
  static final Color _inactiveShadow = Colors.black.withOpacity(0.1);
  static final Color _infoShadow = Colors.black.withOpacity(0.1);

  static const BorderRadius _cardRadius = BorderRadius.all(Radius.circular(24));
  static const BorderRadius _infoRadius = BorderRadius.all(Radius.circular(20));
  static const BorderRadius _categoryRadius = BorderRadius.all(Radius.circular(10));
  static const BorderRadius _buttonRadius = BorderRadius.all(Radius.circular(16));

  static final ButtonStyle _readButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.blue.shade500,
    foregroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: _buttonRadius),
    elevation: 0,
  );

  const _SpotlightCard({
    required this.data,
    required this.docId,
    required this.isActive,
    required this.onTap,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    final String title = data['title'] ?? 'Tanpa Judul';
    final String coverUrl = data['coverUrl'] ?? '';
    final String category = data['category'] ?? 'Cerita';

    final bool isTeacherTask = data['createdBy'] != null && data['createdBy'].toString().isNotEmpty;

    final List<BoxShadow> cardShadow = isActive
        ? [BoxShadow(color: _activeShadow, blurRadius: 25, offset: const Offset(0, 15))]
        : [BoxShadow(color: _inactiveShadow, blurRadius: 10, offset: const Offset(0, 5))];

    return GestureDetector(
      onTap: isActive ? onTap : null,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Hero(
            tag: 'cover_$docId',
            flightShuttleBuilder: (fCtx, anim, dir, fromCtx, toCtx) {
              return Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: _cardRadius,
                  child: _CoverImage(url: coverUrl, title: title, isSpotlight: true),
                ),
              );
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: r.size(240),
                maxHeight: r.size(340),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: _cardRadius,
                  boxShadow: cardShadow,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: _cardRadius,
                      child: _CoverImage(url: coverUrl, title: title, isSpotlight: true),
                    ),
                    if (isTeacherTask)
                      Positioned(
                        top: r.spacing(12),
                        right: r.spacing(12),
                        child: _TeacherBadge(r: r),
                      ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: isActive ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              margin: EdgeInsets.only(top: r.spacing(20)),
              padding: EdgeInsets.symmetric(
                horizontal: r.spacing(16),
                vertical: r.spacing(12),
              ),
              width: r.size(250),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: _infoRadius,
                boxShadow: [
                  BoxShadow(color: _infoShadow, blurRadius: 10, offset: const Offset(0, 5)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: r.spacing(10),
                      vertical: r.spacing(4),
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: _categoryRadius,
                    ),
                    child: Text(
                      category,
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: r.font(10),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: r.spacing(6)),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                      fontSize: r.font(15),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: r.spacing(10)),
                  SizedBox(
                    width: double.infinity,
                    height: r.size(40),
                    child: ElevatedButton(
                      style: _readButtonStyle,
                      onPressed: isActive ? onTap : null,
                      child: Text(
                        'MULAI BACA',
                        style: TextStyle(
                          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                          fontWeight: FontWeight.bold,
                          fontSize: r.font(13),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayfulGridBookCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  final VoidCallback onTap;
  final ResponsiveHelper r;

  static const Map<String, Color> _categoryColors = {
    'dongeng': Color(0xFFBA68C8),
    'legenda': Color(0xFF26A69A),
    'cerpen': Color(0xFF42A5F5),
    'cerita rakyat': Color(0xFF66BB6A),
    'mitos': Color(0xFFEF5350),
  };
  static final Color _defaultCategoryColor = Colors.orange.shade500;

  static const BorderRadius _cardRadius = BorderRadius.all(Radius.circular(24));
  static const BorderRadius _coverRadius = BorderRadius.all(Radius.circular(16));
  static const BorderRadius _bottomRadius = BorderRadius.vertical(bottom: Radius.circular(20));
  static const BorderRadius _badgeRadius = BorderRadius.all(Radius.circular(12));

  const _PlayfulGridBookCard({
    required this.data,
    required this.docId,
    required this.onTap,
    required this.r,
  });

  Color _getCategoryColor(String category) {
    return _categoryColors[category.toLowerCase()] ?? _defaultCategoryColor;
  }

  @override
  Widget build(BuildContext context) {
    final Color catColor = _getCategoryColor(data['category'] ?? '');
    final Color borderColor = catColor.withOpacity(0.5);
    final Color shadowColor = catColor.withOpacity(0.25);
    final Color bgColor = catColor.withOpacity(0.1);

    final bool isTeacherTask = data['createdBy'] != null && data['createdBy'].toString().isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: _cardRadius,
          border: Border.all(color: borderColor, width: 3),
          boxShadow: [
            BoxShadow(color: shadowColor, offset: const Offset(0, 6), blurRadius: 0),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  r.spacing(8), r.spacing(8), r.spacing(8), 0,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(
                      tag: 'cover_$docId',
                      flightShuttleBuilder: (fCtx, anim, dir, fromCtx, toCtx) {
                        return Material(
                          color: Colors.transparent,
                          child: ClipRRect(
                            borderRadius: _coverRadius,
                            child: _CoverImage(
                              url: data['coverUrl'] ?? '',
                              title: data['title'] ?? 'Cerita',
                              isSpotlight: false,
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: _coverRadius,
                        child: _CoverImage(
                          url: data['coverUrl'] ?? '',
                          title: data['title'] ?? 'Cerita',
                          isSpotlight: false,
                        ),
                      ),
                    ),
                    if (isTeacherTask)
                      Positioned(
                        top: r.spacing(8),
                        right: r.spacing(8),
                        child: _TeacherBadge(r: r),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: _bottomRadius,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: r.spacing(6),
                  vertical: r.spacing(4),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text(
                      data['title'] ?? 'Tanpa Judul',
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                        fontSize: r.font(11),
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: r.spacing(14),
                        vertical: r.spacing(4),
                      ),
                      decoration: BoxDecoration(
                        color: catColor,
                        borderRadius: _badgeRadius,
                      ),
                      child: Text(
                        'BACA',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: r.font(10),
                          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  final String url;
  final String title;
  final bool isSpotlight;

  static const LinearGradient _placeholderGradient = LinearGradient(
    colors: [Color(0xFF64B5F6), Color(0xFFCE93D8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  const _CoverImage({
    required this.url,
    required this.title,
    this.isSpotlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return _buildImage(context);
  }

  Widget _buildImage(BuildContext context) {
    if (url.isEmpty) return _buildPlaceholderCover(context);
    try {
      if (url.startsWith('data:image')) {
        return Image.memory(
          base64Decode(url.split(',').last),
          fit: isSpotlight ? BoxFit.contain : BoxFit.cover,
          width: isSpotlight ? null : double.infinity,
          cacheWidth: 400,
          gaplessPlayback: true,
          errorBuilder: (c, o, s) => _buildPlaceholderCover(context),
        );
      } else if (url.startsWith('http')) {
        return CachedNetworkImage(
          imageUrl: url,
          fit: isSpotlight ? BoxFit.contain : BoxFit.cover,
          width: isSpotlight ? null : double.infinity,
          memCacheWidth: 400,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (c, u) => const Center(
            child: CircularProgressIndicator(color: Colors.orange),
          ),
          errorWidget: (c, u, e) => _buildPlaceholderCover(context),
        );
      }
    } catch (e) {
      return _buildPlaceholderCover(context);
    }
    return _buildPlaceholderCover(context);
  }

  Widget _buildPlaceholderCover(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: _placeholderGradient),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_stories, size: 40, color: Colors.white54),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                title,
                maxLines: 3,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}