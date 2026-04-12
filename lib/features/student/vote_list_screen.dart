// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:dylearn/core/services/tutorial_service.dart';
import 'package:dylearn/core/services/vote_service.dart';
import 'package:dylearn/shared/widgets/background_wrapper.dart';
import 'package:dylearn/shared/widgets/vote_card.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:showcaseview/showcaseview.dart';

import 'package:dylearn/core/utils/responsive_helper.dart';

// ══════════════════════════════════════════════════════════════════
// VOTE LIST SCREEN
//
// PERUBAHAN: Tab "Status Bukuku" + MyBookStatusListWidget dihapus.
// Siswa tidak bisa lagi upload buku ke library publik — tab tersebut
// selalu kosong dan ProgressCardWidget untuk isPublicUploadRunning
// tidak akan pernah tampil. Screen disederhanakan jadi satu tampilan
// daftar buku yang bisa divote (Juri Cilik saja).
// ══════════════════════════════════════════════════════════════════

class VoteListScreen extends StatefulWidget {
  const VoteListScreen({super.key});

  @override
  State<VoteListScreen> createState() => _VoteListScreenState();
}

class _VoteListScreenState extends State<VoteListScreen> {
  final VoteService _voteService    = VoteService();
  final User?       _currentUser    = FirebaseAuth.instance.currentUser;

  // Nullable — tidak di-assign jika currentUser == null
  Stream<List<DocumentSnapshot>>? _booksStream;

  bool _isTutorialChecked = false;
  final GlobalKey _votingListKey = GlobalKey();

  late final Map<GlobalKey, String> _showcaseDescriptions;

  // Cache GoogleFonts base → static final
  static final TextStyle _comicNueBase = GoogleFonts.comicNeue(
    fontWeight: FontWeight.bold,
  );

  // Cache AppBar shadow color → static final
  static final Color _appBarShadow = Colors.blue.withOpacity(0.2);

  @override
  void initState() {
    super.initState();
    if (_currentUser != null) {
      _booksStream = _voteService.getBooksToVoteStream(_currentUser.uid);
    }

    _showcaseDescriptions = {
      _votingListKey:
          'Dengarkan cuplikan cerita dari teman-teman, lalu beri nilai Suka atau Tidak Suka! Suaramu menentukan apakah buku itu masuk perpustakaan.',
    };
  }

  void _checkAndStartTutorial(BuildContext showcaseContext) {
    if (!_isTutorialChecked) {
      _isTutorialChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final bool hasSeen =
            await TutorialService.hasSeenTutorial('juri_cilik');
        if (!hasSeen && mounted) {
          ShowCaseWidget.of(showcaseContext)
              .startShowCase([_votingListKey]);
          await TutorialService.markTutorialAsSeen('juri_cilik');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(
        body: Center(child: Text("Silakan login dulu ya!")),
      );
    }

    final ResponsiveHelper r = context.r;

    final TextStyle tooltipStyle = TextStyle(
      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
      fontSize:   r.font(14),
      color:      Colors.black87,
      height:     1.4,
    );

    return ShowCaseWidget(
      onStart: (index, key) {
        final text = _showcaseDescriptions[key];
        if (text != null) TutorialService.speakShowcaseText(text);
      },
      onComplete: (index, key) => TutorialService.stopSpeaking(),
      onFinish:   () => TutorialService.stopSpeaking(),
      builder: (showcaseContext) {
        _checkAndStartTutorial(showcaseContext);

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: AppBar(
            title: Text(
              "Juri Cilik 🏆",
              style: _comicNueBase.copyWith(color: Colors.blue[800]),
            ),
            centerTitle:     true,
            backgroundColor: Colors.white,
            elevation:       2,
            shadowColor:     _appBarShadow,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: Colors.blue[800]),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: BackgroundWrapper(
            child: Showcase(
              key:          _votingListKey,
              description:  _showcaseDescriptions[_votingListKey]!,
              descTextStyle: tooltipStyle,
              child: VotingListWidget(
                booksStream: _booksStream ?? const Stream.empty(),
                r: r,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// VOTING LIST WIDGET
// ══════════════════════════════════════════════════════════════════

class VotingListWidget extends StatelessWidget {
  final Stream<List<DocumentSnapshot>> booksStream;
  final ResponsiveHelper r;

  static final TextStyle _comicNueBase = GoogleFonts.comicNeue(
    fontWeight: FontWeight.bold,
  );

  static final Color _emptyIconColor = Colors.green.withOpacity(0.5);

  const VotingListWidget({
    super.key,
    required this.booksStream,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DocumentSnapshot>>(
      stream: booksStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.orange),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(r.spacing(20)),
              child: Text(
                "Waduh, ada kesalahan jaringan nih.",
                textAlign: TextAlign.center,
                style: _comicNueBase.copyWith(
                  color:      Colors.grey,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
          );
        }

        final books = snapshot.data ?? [];

        if (books.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(r.spacing(32)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: r.size(150),
                    child: RepaintBoundary(
                      child: Lottie.asset(
                        'assets/animations/EMPTY_BOX.json',
                        fit:       BoxFit.contain,
                        frameRate: FrameRate.composition,
                        errorBuilder: (c, e, s) => Icon(
                          Icons.check_circle_outline_rounded,
                          size:  r.size(100),
                          color: _emptyIconColor,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: r.spacing(24)),
                  Text(
                    "Kerja Bagus! 🎉",
                    style: _comicNueBase.copyWith(
                      fontSize: r.font(24),
                      color:    Colors.blue[800],
                    ),
                  ),
                  SizedBox(height: r.spacing(8)),
                  Text(
                    "Kamu sudah menilai semua buku yang ada.\nTunggu teman lain upload buku baru ya!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.fontFamily,
                      fontSize: r.font(14),
                      color:    Colors.grey[600],
                      height:   1.5,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Header sebagai item index 0 agar tidak wrap dalam Column baru
        return ListView.builder(
          physics:    const BouncingScrollPhysics(),
          padding:    EdgeInsets.all(r.spacing(20)),
          itemCount:  books.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) return VotingListHeader(r: r);
            final doc = books[index - 1];
            return VoteCard(key: ValueKey(doc.id), doc: doc);
          },
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// VOTING LIST HEADER
// ══════════════════════════════════════════════════════════════════

class VotingListHeader extends StatelessWidget {
  final ResponsiveHelper r;

  static final Color _bgColor     = Colors.orange.shade50;
  static final Color _borderColor = Colors.orange.shade200;
  static final Color _textColor   = Colors.orange.shade900;

  static final TextStyle _comicNueBase = GoogleFonts.comicNeue(
    fontWeight: FontWeight.bold,
  );

  const VotingListHeader({super.key, required this.r});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:    EdgeInsets.all(r.spacing(12)),
      margin:     EdgeInsets.only(bottom: r.spacing(20)),
      decoration: BoxDecoration(
        color:        _bgColor,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_rounded, color: Colors.orange),
          SizedBox(width: r.spacing(12)),
          Expanded(
            child: Text(
              "Dengarkan cuplikan ceritanya, lalu pilih suka atau tidak ya!",
              style: _comicNueBase.copyWith(
                fontSize: r.font(14),
                color:    _textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}