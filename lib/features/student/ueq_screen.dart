// ignore_for_file: deprecated_member_use, use_build_context_synchronously, avoid_types_as_parameter_names

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/ueq_result.dart';
import '../../shared/providers/settings_provider.dart';
import '../../core/utils/responsive_helper.dart';

// FIX ROOT CAUSE: typedef untuk menghindari parser error
// "ValueListenableBuilder<TextRange?>" di dalam builder closure
// diinterpretasikan Dart sebagai operator < dan >
typedef _NullableTextRange = TextRange?;

class UeqScreen extends StatefulWidget {
  final String docId;
  
  // PARAMETER BARU UNTUK SESI GURU
  final String? activeStudentUid;

  const UeqScreen({
    super.key, 
    required this.docId,
    this.activeStudentUid, // Tambahkan ini agar tidak error
  });

  @override
  State<UeqScreen> createState() => _UeqScreenState();
}

class _UeqScreenState extends State<UeqScreen> {
  final FlutterTts _flutterTts = FlutterTts();

  final ValueNotifier<int> _currentIndexNotifier =
      ValueNotifier<int>(0);
  final ValueNotifier<bool> _isSavingNotifier =
      ValueNotifier<bool>(false);

  final Map<String, int> _answers = {};

  final ValueNotifier<_NullableTextRange> _highlightNotifier =
      ValueNotifier(null);

  // OPTIMIZATION: Cache GoogleFonts base → static final
  static final TextStyle _comicNueBase = GoogleFonts.comicNeue(
    fontWeight: FontWeight.bold,
  );

  // OPTIMIZATION: Cache question card decoration → static final
  static final BoxDecoration _cardDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(30),
    boxShadow: [
      BoxShadow(
        color: Colors.orange.withValues(alpha: 0.1),
        blurRadius: 20,
        offset: const Offset(0, 10),
      ),
    ],
  );

  static const List<Map<String, dynamic>> _questions = [
  // Q1 — Attractiveness
  {
    'id': 'q1',
    'text': 'Saya suka belajar membaca menggunakan aplikasi ini.',
    'icon': Icons.favorite_rounded,
  },
  // Q2 — Perspicuity
  {
    'id': 'q2',
    'text': 'Aplikasi ini sangat mudah untuk saya gunakan.',
    'icon': Icons.lightbulb_rounded,
  },
  // Q3 — Dependability (Font)
  {
    'id': 'q3',
    'text': 'Huruf-huruf di dalam aplikasi ini bentuknya jelas dan mudah saya baca.',
    'icon': Icons.text_fields_rounded,
  },
  // Q4 — Dependability (TTS)
  {
    'id': 'q4',
    'text': 'Suara yang membacakan cerita terdengar jelas dan membantu saya.',
    'icon': Icons.volume_up_rounded,
  },
  // Q5 — Efficiency (OCR)
  {
    'id': 'q5',
    'text': 'Saya bisa dengan mudah memfoto halaman buku agar bisa dibacakan.',
    'icon': Icons.camera_alt_rounded,
  },
  // Q6 — Stimulation (STT)
  {
    'id': 'q6',
    'text': 'Berlatih membaca dengan suara saya sendiri di aplikasi ini terasa menyenangkan.',
    'icon': Icons.mic_rounded,
  },
  // Q7 — Novelty (Visual)
  {
    'id': 'q7',
    'text': 'Gambar, warna, dan tombol di dalam aplikasi ini bagus dan menarik.',
    'icon': Icons.palette_rounded,
  },
  // Q8 — Stimulation (Gamification)
  {
    'id': 'q8',
    'text': 'Aplikasi ini membuat saya ingin belajar membaca lagi besok.',
    'icon': Icons.sentiment_very_satisfied_rounded,
  },
];

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _highlightNotifier.dispose();
    _currentIndexNotifier.dispose();
    _isSavingNotifier.dispose();
    super.dispose();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("id-ID");
    await _flutterTts.awaitSpeakCompletion(true);

    _flutterTts.setProgressHandler(
        (String text, int start, int end, String word) {
      _highlightNotifier.value =
          TextRange(start: start, end: end);
    });

    _flutterTts.setCompletionHandler(() {
      _highlightNotifier.value = null;
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _speakCurrentQuestion();
    });
  }

  Future<void> _speakCurrentQuestion() async {
    if (!mounted) return;
    final settings =
        Provider.of<SettingsProvider>(context, listen: false);

    await _flutterTts.stop();
    _highlightNotifier.value = null;

    if (settings.selectedVoice != null) {
      await _flutterTts.setVoice(settings.selectedVoice!);
    }
    await _flutterTts.setSpeechRate(settings.ttsRate);
    await _flutterTts.setPitch(settings.ttsPitch);

    await _flutterTts
        .speak(_questions[_currentIndexNotifier.value]['text']);
  }

  void _answerQuestion(int score) {
    if (_isSavingNotifier.value) return;

    final String qId =
        _questions[_currentIndexNotifier.value]['id'];
    _answers[qId] = score;

    if (_currentIndexNotifier.value < _questions.length - 1) {
      _currentIndexNotifier.value++;
      _highlightNotifier.value = null;
      _speakCurrentQuestion();
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    _isSavingNotifier.value = true;
    await _flutterTts.stop();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // FIX: Gunakan UID target. Jika Guru yang memegang HP, gunakan UID Anak
    final String targetUid = widget.activeStudentUid ?? user.uid;

    final int total =
        _answers.values.fold(0, (sum, score) => sum + score);

    try {
      String childName = 'Responden';

      // Tarik nama anak dari Firestore berdasarkan targetUid
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(targetUid)
            .get();
        if (userDoc.exists && userDoc.data() != null) {
          final data = userDoc.data()!;
          childName = data['displayName'] ?? childName;
        }
      } catch (e) {
        debugPrint("Gagal ambil profil: $e");
      }

      final result = UeqResult(
        id: '',
        userId: targetUid, // Data disave atas nama anak
        childName: childName,
        timestamp: DateTime.now(),
        docId: widget.docId,
        answers: _answers,
        totalScore: total,
      );

      // 1. Simpan Hasil Survei
      await FirebaseFirestore.instance
          .collection('ueq_results')
          .add(result.toMap());

      // 2. KUNCI SURVEI (Tandai bahwa anak ini sudah mengisi UEQ)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(targetUid)
          .set({'hasCompletedUeq': true}, SetOptions(merge: true));

      if (mounted) _showCompletionDialog();
    } catch (e) {
      debugPrint("Error save UEQ: $e");
      if (mounted) {
        _isSavingNotifier.value = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal menyimpan: $e")),
        );
      }
    }
  }

  void _showCompletionDialog() {
    final String? fontFamily =
        Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final ResponsiveHelper r = context.r;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30)),
        title: Text(
          "Terima Kasih! 🌟",
          textAlign: TextAlign.center,
          style: _comicNueBase.copyWith(
            fontSize: r.font(28),
            color: Colors.orange,
          ),
        ),
        content: Text(
          "Pendapatmu sangat berharga untuk membuat aplikasi ini lebih baik.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: r.font(16),
          ),
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: const StadiumBorder(),
                padding: EdgeInsets.symmetric(
                  horizontal: r.spacing(40),
                  vertical: r.spacing(15),
                ),
              ),
              onPressed: () {
                Navigator.pop(c); // Tutup dialog UEQ
                Navigator.pop(context); // Tutup layar UEQ, kembali ke Perpus
              },
              child: Text(
                "Selesai",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: r.font(18),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(height: r.spacing(10)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ResponsiveHelper r = context.r;
    final String? fontFamily =
        Theme.of(context).textTheme.bodyMedium?.fontFamily;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBE6),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.grey),
          onPressed: () => Navigator.pop(context),
        ),
        title: ValueListenableBuilder<int>(
          valueListenable: _currentIndexNotifier,
          builder: (context, currentIndex, child) {
            return Text(
              "Survei Singkat (${currentIndex + 1}/${_questions.length})",
              style: _comicNueBase.copyWith(
                color: Colors.black87,
              ),
            );
          },
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(r.spacing(20)),
          child: Column(
            children: [
              // Progress bar
              RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: ValueListenableBuilder<int>(
                    valueListenable: _currentIndexNotifier,
                    builder: (context, currentIndex, child) {
                      return TweenAnimationBuilder<double>(
                        duration:
                            const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        tween: Tween<double>(
                          begin: 0,
                          end: (currentIndex + 1) /
                              _questions.length,
                        ),
                        builder: (context, value, _) =>
                            LinearProgressIndicator(
                          value: value,
                          minHeight: r.size(10),
                          backgroundColor: Colors.white,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(
                                  Colors.orange),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const Spacer(),

              // Question card
              RepaintBoundary(
                child: ValueListenableBuilder<int>(
                  valueListenable: _currentIndexNotifier,
                  builder: (context, currentIndex, child) {
                    final q = _questions[currentIndex];
                    return AnimatedSwitcher(
                      duration:
                          const Duration(milliseconds: 500),
                      child: Container(
                        key: ValueKey(currentIndex),
                        width: double.infinity,
                        padding: EdgeInsets.all(r.spacing(25)),
                        decoration: _cardDecoration,
                        child: Column(
                          children: [
                            Icon(
                              q['icon'] as IconData,
                              size: r.size(60),
                              color: Colors.orange,
                            ),
                            SizedBox(height: r.spacing(20)),
                            GestureDetector(
                              onTap: _speakCurrentQuestion,
                              child: _QuestionHighlightWrapper(
                                highlightNotifier:
                                    _highlightNotifier,
                                text: q['text'] as String,
                                fontFamily: fontFamily,
                                r: r,
                              ),
                            ),
                            SizedBox(height: r.spacing(10)),
                            Icon(
                              Icons.volume_up_rounded,
                              color: Colors.blue,
                              size: r.size(30),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const Spacer(),

              Text(
                "Pilih ikon yang sesuai perasaanmu:",
                style: _comicNueBase.copyWith(
                  fontSize: r.font(20),
                  color: Colors.grey[700],
                ),
              ),
              SizedBox(height: r.spacing(20)),

              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceEvenly,
                children: [
                  _SmileyButton(
                    emoji: "☹️",
                    score: 1,
                    color: Colors.red,
                    label: "Tidak/Susah",
                    onTap: _answerQuestion,
                    r: r,
                  ),
                  _SmileyButton(
                    emoji: "😐",
                    score: 2,
                    color: Colors.amber,
                    label: "Biasa",
                    onTap: _answerQuestion,
                    r: r,
                  ),
                  _SmileyButton(
                    emoji: "😄",
                    score: 3,
                    color: Colors.green,
                    label: "Iya/Mudah",
                    onTap: _answerQuestion,
                    r: r,
                  ),
                ],
              ),

              SizedBox(height: r.spacing(35)),

              ValueListenableBuilder<bool>(
                valueListenable: _isSavingNotifier,
                builder: (context, isSaving, child) {
                  return isSaving
                      ? const CircularProgressIndicator(
                          color: Colors.orange)
                      : const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// QUESTION HIGHLIGHT WRAPPER
// ══════════════════════════════════════════════════════════════════

class _QuestionHighlightWrapper extends StatelessWidget {
  final ValueNotifier<_NullableTextRange> highlightNotifier;
  final String text;
  final String? fontFamily;
  final ResponsiveHelper r;

  const _QuestionHighlightWrapper({
    required this.highlightNotifier,
    required this.text,
    required this.fontFamily,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_NullableTextRange>(
      valueListenable: highlightNotifier,
      builder: (context, range, _) {
        return _HighlightedQuestionText(
          text: text,
          range: range,
          fontFamily: fontFamily,
          r: r,
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// HIGHLIGHTED QUESTION TEXT
// ══════════════════════════════════════════════════════════════════

class _HighlightedQuestionText extends StatelessWidget {
  final String text;
  final TextRange? range;
  final String? fontFamily;
  final ResponsiveHelper r;

  static const TextStyle _highlightStyle = TextStyle(
    backgroundColor: Colors.orange,
    color: Colors.white,
  );

  const _HighlightedQuestionText({
    required this.text,
    required this.r,
    this.range,
    this.fontFamily,
  });

  @override
  Widget build(BuildContext context) {
    final TextStyle baseStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: r.font(22),
      height: 1.5,
      fontWeight: FontWeight.bold,
      color: Colors.black87,
    );

    if (range == null ||
        range!.start < 0 ||
        range!.end > text.length) {
      return Text(
        text,
        textAlign: TextAlign.center,
        style: baseStyle,
      );
    }

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: text.substring(0, range!.start)),
          TextSpan(
            text: text.substring(range!.start, range!.end),
            style: _highlightStyle,
          ),
          TextSpan(text: text.substring(range!.end)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// SMILEY BUTTON
// ══════════════════════════════════════════════════════════════════

class _SmileyButton extends StatelessWidget {
  final String emoji;
  final int score;
  final Color color;
  final String label;
  final Function(int) onTap;
  final ResponsiveHelper r;

  static final TextStyle _comicNueBase = GoogleFonts.comicNeue(
    fontWeight: FontWeight.bold,
  );

  // FIX: getter menghindari withOpacity() dipanggil ulang setiap build()
  Color get _borderColor => color.withOpacity(0.5);
  Color get _shadowColor => color.withOpacity(0.2);

  const _SmileyButton({
    required this.emoji,
    required this.score,
    required this.color,
    required this.label,
    required this.onTap,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    final Color borderColor = _borderColor;
    final Color shadowColor = _shadowColor;

    return Column(
      children: [
        GestureDetector(
          onTap: () => onTap(score),
          child: Container(
            padding: EdgeInsets.all(r.spacing(15)),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: borderColor, width: 4),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Text(
              emoji,
              style: TextStyle(fontSize: r.font(45)),
            ),
          ),
        ),
        SizedBox(height: r.spacing(8)),
        Text(
          label,
          textAlign: TextAlign.center,
          style: _comicNueBase.copyWith(
            color: color,
            fontSize: r.font(14),
            height: 1.1,
          ),
        ),
      ],
    );
  }
}