// ignore_for_file: deprecated_member_use, unused_field, use_build_context_synchronously, prefer_conditional_assignment, prefer_final_fields, unnecessary_import, curly_braces_in_flow_control_structures, library_private_types_in_public_api, unnecessary_underscores

import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:math';
import 'package:dylearn/shared/widgets/practice_mic_panel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../shared/providers/settings_provider.dart';
import '../core/utils/text_utils.dart';
import '../core/utils/responsive_helper.dart';
import '../shared/widgets/reading_ruler.dart';
import 'student/ueq_screen.dart';

import '../core/services/ocr_service.dart';
import '../core/services/notification_service.dart';

import '../core/models/reading_session.dart';
import '../core/utils/reading_evaluator.dart';
import '../core/services/stt_service.dart';

import '../shared/widgets/image_components.dart';
import '../shared/widgets/setting_components.dart';
import '../shared/widgets/control_components.dart';
import '../shared/widgets/reading_components.dart';
import '../shared/widgets/dialog_components.dart';

typedef _NullableTextRange = TextRange?;

class ReadScreen extends StatefulWidget {
  final String? text;
  final String documentId;
  final int initialIndex;
  final List<String>? imageUrls;
  
  // PARAMETER BARU UNTUK SESI PENDAMPINGAN GURU
  final String? activeStudentUid;

  const ReadScreen({
    super.key,
    required this.text,
    required this.documentId,
    this.initialIndex = 0,
    this.imageUrls,
    this.activeStudentUid,
  });

  @override
  State<ReadScreen> createState() => _ReadScreenState();
}

enum TtsState { playing, stopped, paused }

class _ReadScreenState extends State<ReadScreen> with WidgetsBindingObserver {
  final FlutterTts _flutterTts = FlutterTts();

  final ValueNotifier<_NullableTextRange> _highlightNotifier =
      ValueNotifier(null);
  final ValueNotifier<TtsState> _ttsStateNotifier =
      ValueNotifier(TtsState.stopped);
  final ValueNotifier<String> _currentImageUrlNotifier = ValueNotifier("");
  final ValueNotifier<bool> _isScreenLockedNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _isShowingFullImageNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _isPracticeModeNotifier = ValueNotifier(false);

  final PageController _textPageController = PageController();
  final PageController _imagePageController = PageController();
  PageController? _overlayPageController;

  final Map<int, GlobalKey> _itemKeys = {};

  // ══════════════════════════════════════════════════════════════════════════
  // STATE LATIHAN
  // ══════════════════════════════════════════════════════════════════════════
  final Map<int, List<WordEvaluation>> _evaluationResults = {};
  DateTime? _practiceStartTime;
  
  // Menyimpan posisi terakhir yang dilatih untuk fitur resume
  int _lastPracticeSentenceIndex = 0; 

  bool _isLoadingText = true;
  bool _isTtsReady = false;
  bool _hasReadSomething = false;
  bool _isSyncingPage = false;
  bool _isOverlayZoomed = false;

  List<String> _sentences = [];
  List<String> _syllabifiedSentences = [];
  List<String> _displayImages = [];
  List<int> _sentenceToImageMap = [];
  List<List<int>> _pages = [];

  int _currentSentenceIndex = 0;
  int _currentVisualPage = 0;
  bool _isImageReady = false;
  Completer<void>? _imageLoadCompleter;

  int _lastWordStart = 0;
  int _lastWordEnd = 0;

  DateTime? _startTime;
  Timer? _durationTimer;

  String _bookTitle = "Cerita ini";

  static final Color _bgBlurOverlay = Colors.black.withOpacity(0.6);
  static final Color _progressBgColor = Colors.orange.withOpacity(0.2);
  static final Color _fullscreenBgColor = Colors.black.withOpacity(0.9);
  static final TextStyle _comicNueBase =
      GoogleFonts.comicNeue(fontWeight: FontWeight.bold);

  static const List<Map<String, String>> _availableFonts = [
    {'name': 'OpenDyslexic', 'label': 'OpenDyslexic'},
    {'name': 'TrikaIndoDyslexic3', 'label': 'Trika Indo Dyslexic'},
    {'name': 'ComicNeue', 'label': 'Comic Neue'},
    {'name': 'Poppins', 'label': 'Poppins'},
    {'name': 'Inter', 'label': 'Inter'},
  ];

  // HELPER UNTUK MENDAPATKAN UID TARGET (Guru atau Murid)
  String get _targetUid => widget.activeStudentUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Inisialisasi awal, akan di-overwrite oleh fetchFromFirestore jika ada data
    _currentSentenceIndex = widget.initialIndex;
    if (widget.imageUrls != null && widget.imageUrls!.isNotEmpty) {
      _displayImages = widget.imageUrls!;
      _currentImageUrlNotifier.value = _displayImages.first;
    }
    _initData();
    _startTracking();
    _initTts();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // DATA LOADING
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _initData() async {
    await _fetchFromFirestore();
  }

  Future<void> _fetchFromFirestore() async {
    if (widget.documentId.isEmpty || widget.documentId == 'offline_id') {
      if (mounted) setState(() => _isLoadingText = false);
      return;
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoadingText = false);
        return;
      }
      
      // MENGGUNAKAN TARGET UID (Bisa UID Anak jika sedang dalam sesi guru)
      final bookDocRef = FirebaseFirestore.instance
          .collection('users').doc(_targetUid) 
          .collection('my_library').doc(widget.documentId);

      DocumentSnapshot<Map<String, dynamic>> doc;
      try {
        doc = await bookDocRef.get().timeout(const Duration(seconds: 3));
      } catch (e) {
        doc = await bookDocRef.get(const GetOptions(source: Source.cache));
      }

      if (doc.exists && mounted) {
        final data = doc.data()!;
        
        // 1. Ambil data dasar buku
        _bookTitle = data['title'] ?? "Cerita ini";
        if (data['imageUrls'] is List) {
          _displayImages = List<String>.from(data['imageUrls']);
        } else if (data['imageUrl'] != null) {
          _displayImages = [data['imageUrl']];
        }

        // 2. Load Progress Mendengarkan & Latihan
        int firestoreSentenceIdx = data['lastSentenceIndex'] ?? widget.initialIndex;
        int firestorePracticeIdx = data['lastPracticeSentenceIndex'] ?? 0;

        _currentSentenceIndex = firestoreSentenceIdx;
        _lastPracticeSentenceIndex = firestorePracticeIdx;
        _lastWordStart = data['lastWordStart'] ?? 0;
        _lastWordEnd = data['lastWordEnd'] ?? 0;

        // 3. LOAD DATA EVALUASI (Warna Kata)
        try {
          final latihanDocs = await bookDocRef.collection('latihan').get();
          final Map<int, List<WordEvaluation>> loadedEvals = {};
          
          for (var lDoc in latihanDocs.docs) {
            final lData = lDoc.data();
            final int? sIndex = int.tryParse(lDoc.id);
            if (sIndex != null && lData['evaluationDetails'] != null) {
              final List<dynamic> evalsRaw = lData['evaluationDetails'];
              loadedEvals[sIndex] = evalsRaw
                  .whereType<Map<String, dynamic>>()
                  .map((e) => WordEvaluation.fromMap(e))
                  .toList();
            }
          }
          _evaluationResults.clear();
          _evaluationResults.addAll(loadedEvals);
        } catch (e) {
          debugPrint("Gagal load data evaluasi latihan: $e");
        }

        // 4. Proses Teks
        final text = data['ocrText'] ?? widget.text ?? "";
        if (text.isNotEmpty) {
          await _processText(text);
        } else {
          setState(() => _isLoadingText = false);
        }
      } else {
        setState(() => _isLoadingText = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingText = false);
    }
  }

  Future<void> _processText(String rawText) async {
    final ProcessedTextData data =
        await compute(OcrService.buildTtsReadyOutput, rawText);
    if (mounted) {
      setState(() {
        _sentences = data.sentences;
        _syllabifiedSentences = data.syllabifiedSentences;
        _sentenceToImageMap = data.sentenceToPageMap;
        _pages = data.pages;
        _isLoadingText = false;
        
        // Proteksi index
        if (_currentSentenceIndex >= _sentences.length) {
          _currentSentenceIndex = max(0, _sentences.length - 1);
        }
        if (_lastPracticeSentenceIndex >= _sentences.length) {
          _lastPracticeSentenceIndex = max(0, _sentences.length - 1);
        }

        _currentVisualPage = _getPageIndexForSentence(_currentSentenceIndex);
        _updateActiveImage();
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _jumpToStoredProgress();
        });
      });
    }
  }

  void _jumpToStoredProgress() {
    if (!mounted) return;
    
    // Jump PageView
    if (_textPageController.hasClients) {
      _textPageController.jumpToPage(_currentVisualPage);
    }
    if (_imagePageController.hasClients) {
      _imagePageController.jumpToPage(_currentVisualPage);
    }
    
    // Highlight kata terakhir (TTS)
    if (_lastWordStart > 0 || _lastWordEnd > 0) {
      _highlightNotifier.value = TextRange(start: _lastWordStart, end: _lastWordEnd);
    }
    
    // Scroll ke item spesifik
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _scrollToActiveSentence(isInitialLoad: true);
    });
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TTS
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _initTts() async {
    try {
      if (Platform.isAndroid) {
        await _flutterTts.setEngine("com.google.android.tts");
      }
      _flutterTts.setStartHandler(() {
        if (mounted) _ttsStateNotifier.value = TtsState.playing;
      });
      _flutterTts.setCompletionHandler(() => _nextSentence());
      _flutterTts.setProgressHandler((text, start, end, word) {
        _highlightNotifier.value = TextRange(start: start, end: end);
        _lastWordStart = start;
        _lastWordEnd = end;
      });
      _flutterTts.setErrorHandler((msg) {
        if (mounted) _ttsStateNotifier.value = TtsState.stopped;
      });
      await _flutterTts.awaitSpeakCompletion(true);
      await _flutterTts.setLanguage("id-ID");
      if (mounted) setState(() => _isTtsReady = true);
    } catch (e) {
      debugPrint("TTS Error: $e");
    }
  }

  Future<void> _speakCurrentSentence() async {
    if (_sentences.isEmpty) return;
    if (!_isImageReady && _currentImageUrlNotifier.value.isNotEmpty) {
      _imageLoadCompleter = Completer();
      await _imageLoadCompleter!.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => debugPrint("⚠️ Timeout gambar"),
      );
    }
    if (!mounted || _ttsStateNotifier.value != TtsState.playing) return;
    _highlightNotifier.value = null;
    _lastWordStart = 0;
    _lastWordEnd = 0;
    _hasReadSomething = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToActiveSentence(isInitialLoad: false);
    });
    final settings = context.read<SettingsProvider>();
    final String text = _sentences[_currentSentenceIndex];
    try {
      await _flutterTts.setSpeechRate(settings.ttsRate);
      await _flutterTts.setPitch(settings.ttsPitch);
      if (settings.selectedVoice != null) {
        await _flutterTts.setVoice(settings.selectedVoice!);
      }
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint("Speak Error: $e");
    }
  }

  void _togglePlayPause() {
    if (_ttsStateNotifier.value == TtsState.playing) {
      _flutterTts.stop();
      _ttsStateNotifier.value = TtsState.paused;
      _saveReadingProgress();
    } else {
      _ttsStateNotifier.value = TtsState.playing;
      _speakCurrentSentence();
    }
  }

  void _nextSentence() {
    if (_currentSentenceIndex < _sentences.length - 1) {
      if (mounted && _ttsStateNotifier.value == TtsState.playing) {
        setState(() => _currentSentenceIndex++);
        _checkAndSyncPageForward();
        _speakCurrentSentence();
        _saveReadingProgress();
      }
    } else {
      _finishReading();
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FUNGSI UEQ & SELESAI
  // ════════════════════════════════════════════════════════════════════════════

  // FUNGSI BARU: Mengecek apakah anak sudah pernah mengisi UEQ
  Future<void> _checkAndRouteToUeq() async {
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.orange))
    );

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_targetUid).get();
      final bool hasCompletedUeq = doc.data()?['hasCompletedUeq'] ?? false;
      
      if (!mounted) return;
      Navigator.pop(context); // Tutup loading

      if (hasCompletedUeq) {
        // Jika sudah pernah isi UEQ, langsung tutup halaman baca kembali ke perpus
        Navigator.pop(context); 
      } else {
        // Jika belum, arahkan ke halaman UEQ (Akan membawa parameter UID Target)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => UeqScreen(
              docId: widget.documentId,
              activeStudentUid: widget.activeStudentUid, // Teruskan parameter guru jika ada
            )
          ),
        );
      }
    } catch (e) {
      debugPrint("Gagal mengecek status UEQ: $e");
      if (mounted) {
        Navigator.pop(context); // Tutup loading
        Navigator.pop(context); // Fallback: Tutup halaman baca
      }
    }
  }

  void _finishReading() {
    _ttsStateNotifier.value = TtsState.stopped;
    _saveReadingProgress();
    
    if (_hasReadSomething) {
      showDialog(
        context: context,
        builder: (c) => FinishDialog(
          onSurvey: () {
            Navigator.pop(c); // Tutup FinishDialog
            _checkAndRouteToUeq(); // Cek & Arahkan ke UEQ
          },
          onClose: () {
            Navigator.pop(c); // Tutup FinishDialog
            Navigator.pop(context); // Kembali ke Perpus
          },
        ),
      );
    } else {
      Navigator.pop(context);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // MODE LATIHAN
  // ════════════════════════════════════════════════════════════════════════════

  void _togglePracticeMode() {
    if (_ttsStateNotifier.value == TtsState.playing) {
      _flutterTts.stop();
      _ttsStateNotifier.value = TtsState.stopped;
    }
    
    final entering = !_isPracticeModeNotifier.value;
    
    if (entering) {
      _practiceStartTime = DateTime.now();
      // KRUSIAL: Pindahkan index kalimat ke posisi terakhir latihan yang tersimpan
      setState(() {
        _currentSentenceIndex = _lastPracticeSentenceIndex;
        _currentVisualPage = _getPageIndexForSentence(_currentSentenceIndex);
      });
      
      // Sinkronisasi visual agar tab latihan terbuka di posisi yang benar
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_textPageController.hasClients) {
          _textPageController.jumpToPage(_currentVisualPage);
        }
        if (_imagePageController.hasClients) {
          _imagePageController.jumpToPage(_currentVisualPage);
        }
        _scrollToActiveSentence(isInitialLoad: true);
      });
    } else {
      _savePracticeProgress();
    }
    
    _isPracticeModeNotifier.value = entering;
  }

  void _practiceNext() {
    if (_currentSentenceIndex < _sentences.length - 1) {
      setState(() {
        _currentSentenceIndex++;
        _lastPracticeSentenceIndex = _currentSentenceIndex;
      });
      _checkAndSyncPageForward();
      // Scroll ke kalimat aktif jika masih dalam halaman yang sama
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToActiveSentence(isInitialLoad: false),
      );
      _savePracticeProgress();
    }
  }

  void _practicePrev() {
    if (_currentSentenceIndex > 0) {
      setState(() {
        _currentSentenceIndex--;
        _lastPracticeSentenceIndex = _currentSentenceIndex;
      });
      _checkAndSyncPageForward();
      // Scroll ke kalimat aktif jika masih dalam halaman yang sama
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToActiveSentence(isInitialLoad: false),
      );
      _savePracticeProgress();
    }
  }

  void _handlePracticeResult(String recognizedText) {
    if (_sentences.isEmpty || recognizedText.isEmpty) return;
    final originalText = _sentences[_currentSentenceIndex];
    final evaluations =
        ReadingEvaluator.evaluateReading(originalText, recognizedText);

    setState(() {
      _evaluationResults[_currentSentenceIndex] = evaluations;
      _lastPracticeSentenceIndex = _currentSentenceIndex;
    });
    _hasReadSomething = true;

    _saveSingleSessionToFirestore(
      sentenceIndex: _currentSentenceIndex,
      originalText: originalText,
      spokenText: recognizedText,
      evaluations: evaluations,
    );
    _savePracticeProgress();
  }

  void _handleFinishAll() {
    if (_evaluationResults.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Belum ada kalimat yang dilatih. Tekan tombol mic dulu ya! 😊',
          style: GoogleFonts.comicNeue(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    final int durationSecs = _practiceStartTime != null
        ? DateTime.now().difference(_practiceStartTime!).inSeconds
        : 0;
    final Map<int, String> sentenceTexts = {
      for (final idx in _evaluationResults.keys) idx: _sentences[idx]
    };
    final summary = PracticeSummary.compute(
      userId: _targetUid, // MENGGUNAKAN TARGET UID
      bookId: widget.documentId,
      bookTitle: _bookTitle,
      totalSentencesInBook: _sentences.length,
      allEvaluations: _evaluationResults,
      sentenceTexts: sentenceTexts,
      totalDurationSeconds: durationSecs,
    );
    
    _saveSummaryToFirestore(summary);
    _savePracticeCompletedFlag(summary.avgAccuracy);
    
    _isPracticeModeNotifier.value = false;
    _showPracticeSummaryDialog(summary);
  }

  void _showPracticeSummaryDialog(PracticeSummary summary) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PracticeSummaryDialog(
        summary: summary,
        onClose: () {
          Navigator.pop(ctx); // Tutup dialog rekap
          _checkAndRouteToUeq(); // Langsung Cek & Arahkan ke UEQ
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // FIRESTORE
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _saveSingleSessionToFirestore({
    required int sentenceIndex,
    required String originalText,
    required String spokenText,
    required List<WordEvaluation> evaluations,
  }) async {
    if (widget.documentId.isEmpty || widget.documentId == 'offline_id') return;
    try {
      final session = ReadingSession.fromEvaluation(
        userId: _targetUid, // MENGGUNAKAN TARGET UID
        bookId: widget.documentId,
        bookTitle: _bookTitle,
        sentenceIndex: sentenceIndex,
        originalText: originalText,
        spokenText: spokenText,
        accuracyScore: ReadingEvaluator.calculateOverallAccuracy(evaluations),
        evaluationDetails: evaluations,
      );
      
      await FirebaseFirestore.instance
          .collection('users').doc(_targetUid) // MENGGUNAKAN TARGET UID
          .collection('my_library').doc(widget.documentId)
          .collection('latihan') 
          .doc(sentenceIndex.toString()) 
          .set(session.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint("Gagal menyimpan sesi latihan: $e");
    }
  }

  Future<void> _saveSummaryToFirestore(PracticeSummary summary) async {
    if (widget.documentId.isEmpty || widget.documentId == 'offline_id') return;
    try {
      await FirebaseFirestore.instance
          .collection('users').doc(_targetUid) // MENGGUNAKAN TARGET UID
          .collection('my_library').doc(widget.documentId)
          .collection('rekap_latihan') 
          .doc('total_rekap') 
          .set(summary.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint("Gagal menyimpan rekap latihan: $e");
    }
  }

  Future<void> _savePracticeProgress() async {
    if (widget.documentId.isEmpty || widget.documentId == 'offline_id') return;
    try {
      await FirebaseFirestore.instance
          .collection('users').doc(_targetUid) // MENGGUNAKAN TARGET UID
          .collection('my_library').doc(widget.documentId)
          .set({
        'lastPracticeSentenceIndex': _lastPracticeSentenceIndex,
        'practiceLastAccessed': FieldValue.serverTimestamp(),
        'practiceTotalUniqueSentences': _evaluationResults.length,
        'practiceInProgress': true,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Gagal menyimpan progress latihan: $e");
    }
  }

  Future<void> _savePracticeCompletedFlag(double avgAccuracy) async {
    if (widget.documentId.isEmpty || widget.documentId == 'offline_id') return;
    try {
      await FirebaseFirestore.instance
          .collection('users').doc(_targetUid) // MENGGUNAKAN TARGET UID
          .collection('my_library').doc(widget.documentId)
          .set({
        'practiceInProgress': false,
        'lastPracticeAvgScore': avgAccuracy,
        'practiceCompletedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Gagal menyimpan flag selesai latihan: $e");
    }
  }

  Future<void> _saveReadingProgress() async {
    if (widget.documentId.isEmpty || widget.documentId == 'offline_id') return;
    if (_startTime == null) return;
    try {
      final int secs = DateTime.now().difference(_startTime!).inSeconds;
      _startTime = DateTime.now();
      await FirebaseFirestore.instance
          .collection('users').doc(_targetUid) // MENGGUNAKAN TARGET UID
          .collection('my_library').doc(widget.documentId)
          .set({
        'lastSentenceIndex': _currentSentenceIndex,
        'lastWordStart': _lastWordStart,
        'lastWordEnd': _lastWordEnd,
        'durationInSeconds': FieldValue.increment(secs),
        'lastAccessed': FieldValue.serverTimestamp(),
        'isFinished': (_currentSentenceIndex >= _sentences.length - 1),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PAGE / SCROLL
  // ════════════════════════════════════════════════════════════════════════════

  void _checkAndSyncPageForward() {
    final targetPage = _getPageIndexForSentence(_currentSentenceIndex);
    if (targetPage != _currentVisualPage) {
      _syncPages(targetPage, autoPlayNext: true);
    }
  }

  void _scrollToActiveSentence({bool isInitialLoad = false}) {
    if (_pages.isEmpty || _currentVisualPage >= _pages.length) return;
    final key = _itemKeys[_currentSentenceIndex];
    if (key == null || key.currentContext == null) return;
    try {
      Scrollable.ensureVisible(
        key.currentContext!,
        alignment: 0.05,
        duration: isInitialLoad
            ? const Duration(milliseconds: 50)
            : const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      debugPrint("Scroll Error: $e");
    }
  }

  void _syncPages(int targetPage,
      {bool fromImage = false,
      bool fromText = false,
      bool fromOverlay = false,
      bool autoPlayNext = false}) {
    if (_isSyncingPage) return;
    _isSyncingPage = true;
    const dur = Duration(milliseconds: 400);
    const curve = Curves.easeInOut;
    if (fromImage) {
      if (_textPageController.hasClients) {
        _textPageController.animateToPage(targetPage, duration: dur, curve: curve);
      }
      if (_overlayPageController?.hasClients == true &&
          _overlayPageController?.page?.round() != targetPage) {
        _overlayPageController!.animateToPage(targetPage, duration: dur, curve: curve);
      }
    } else if (fromText) {
      if (_imagePageController.hasClients) {
        _imagePageController.animateToPage(targetPage, duration: dur, curve: curve);
      }
      if (_overlayPageController?.hasClients == true &&
          _overlayPageController?.page?.round() != targetPage) {
        _overlayPageController!.animateToPage(targetPage, duration: dur, curve: curve);
      }
    } else if (fromOverlay) {
      if (_textPageController.hasClients) {
        _textPageController.animateToPage(targetPage, duration: dur, curve: curve);
      }
      if (_imagePageController.hasClients) {
        _imagePageController.animateToPage(targetPage, duration: dur, curve: curve);
      }
    } else if (autoPlayNext) {
      if (_textPageController.hasClients) {
        _textPageController.animateToPage(targetPage, duration: dur, curve: curve);
      }
      if (_imagePageController.hasClients) {
        _imagePageController.animateToPage(targetPage, duration: dur, curve: curve);
      }
      if (_overlayPageController?.hasClients == true &&
          _overlayPageController?.page?.round() != targetPage) {
        _overlayPageController!.animateToPage(targetPage, duration: dur, curve: curve);
      }
    }
    if (!autoPlayNext) _flutterTts.stop();
    setState(() {
      _currentVisualPage = targetPage;
      _isOverlayZoomed = false;
      if (!autoPlayNext &&
          _pages.isNotEmpty &&
          targetPage < _pages.length &&
          _pages[targetPage].isNotEmpty) {
        if (!_pages[targetPage].contains(_currentSentenceIndex)) {
          _currentSentenceIndex = _pages[targetPage].first;
          _ttsStateNotifier.value = TtsState.paused;
          _highlightNotifier.value = null;
          _lastWordStart = 0;
          _lastWordEnd = 0;
        }
      }
      _updateActiveImage();
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      _isSyncingPage = false;
      _scrollToActiveSentence(isInitialLoad: false);
    });
  }

  void _updateActiveImage() {
    if (_displayImages.isEmpty) return;
    int imgIndex = (_sentenceToImageMap.isNotEmpty &&
            _currentSentenceIndex < _sentenceToImageMap.length)
        ? _sentenceToImageMap[_currentSentenceIndex]
        : 0;
    final String url =
        _displayImages[min(imgIndex, _displayImages.length - 1)];
    if (url != _currentImageUrlNotifier.value) {
      _currentImageUrlNotifier.value = url;
      _isImageReady = false;
      if (imgIndex + 1 < _displayImages.length &&
          _displayImages[imgIndex + 1].startsWith('http')) {
        precacheImage(
            CachedNetworkImageProvider(_displayImages[imgIndex + 1]), context);
      }
    }
  }

  void _onImageLoaded() {
    if (!_isImageReady) {
      _isImageReady = true;
      _imageLoadCompleter?.complete();
      _imageLoadCompleter = null;
    }
  }

  int _getPageIndexForSentence(int index) {
    for (int i = 0; i < _pages.length; i++) {
      if (_pages[i].contains(index)) return i;
    }
    return 0;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // EDIT / DELETE KALIMAT
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _editSentenceAndSave(int indexToEdit, String newText) async {
    StringBuffer buf = StringBuffer();
    int curImg = _sentenceToImageMap.isNotEmpty ? _sentenceToImageMap.first : 0;
    for (int i = 0; i < _sentences.length; i++) {
      int imgIdx = (_sentenceToImageMap.isNotEmpty &&
              i < _sentenceToImageMap.length)
          ? _sentenceToImageMap[i]
          : 0;
      if (i > 0 && imgIdx != curImg) {
        buf.write("\n\n<PAGE_BREAK>\n\n");
        curImg = imgIdx;
      } else if (i > 0) {
        buf.write("\n\n");
      }
      buf.write(i == indexToEdit ? newText : _sentences[i]);
    }
    await _saveToFirestoreAndReparse(buf.toString());
  }

  Future<void> _deleteSentenceAndSave(int indexToDelete) async {
    StringBuffer buf = StringBuffer();
    int curImg = _sentenceToImageMap.isNotEmpty ? _sentenceToImageMap.first : 0;
    bool firstAdded = false;
    for (int i = 0; i < _sentences.length; i++) {
      if (i == indexToDelete) continue;
      int imgIdx = (_sentenceToImageMap.isNotEmpty &&
              i < _sentenceToImageMap.length)
          ? _sentenceToImageMap[i]
          : 0;
      if (firstAdded) {
        if (imgIdx != curImg) {
          buf.write("\n\n<PAGE_BREAK>\n\n");
          curImg = imgIdx;
        } else {
          buf.write("\n\n");
        }
      } else {
        curImg = imgIdx;
        firstAdded = true;
      }
      buf.write(_sentences[i]);
    }
    await _saveToFirestoreAndReparse(buf.toString());
  }

  Future<void> _saveToFirestoreAndReparse(String reconstructedText) async {
    setState(() => _isLoadingText = true);
    if (widget.documentId.isNotEmpty && widget.documentId != 'offline_id') {
      try {
        await FirebaseFirestore.instance
            .collection('users').doc(_targetUid) // MENGGUNAKAN TARGET UID
            .collection('my_library').doc(widget.documentId)
            .set({'ocrText': reconstructedText}, SetOptions(merge: true));
      } catch (e) {
        debugPrint("Gagal menyimpan teks: $e");
      }
    }
    await _processText(reconstructedText);
  }

  // ════════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ════════════════════════════════════════════════════════════════════════════

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _flutterTts.stop();
      _saveReadingProgress();
      if (_isPracticeModeNotifier.value) {
        _savePracticeProgress();
      }
    }
  }

  void _startTracking() => _startTime = DateTime.now();

  void _scheduleReminderIfNeeded() {
    if (_sentences.isNotEmpty &&
        _currentSentenceIndex < _sentences.length - 1) {
      NotificationService().scheduleReadingReminder(_bookTitle);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveReadingProgress();
    if (_isPracticeModeNotifier.value || _evaluationResults.isNotEmpty) {
      _savePracticeProgress();
    }
    _durationTimer?.cancel();
    _flutterTts.stop();
    _textPageController.dispose();
    _imagePageController.dispose();
    _overlayPageController?.dispose();
    _highlightNotifier.dispose();
    _ttsStateNotifier.dispose();
    _currentImageUrlNotifier.dispose();
    _isScreenLockedNotifier.dispose();
    _isShowingFullImageNotifier.dispose();
    _isPracticeModeNotifier.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    if (_isPracticeModeNotifier.value) {
      _savePracticeProgress();
      _isPracticeModeNotifier.value = false;
      return false;
    }
    if (_isShowingFullImageNotifier.value) {
      _isShowingFullImageNotifier.value = false;
      _isOverlayZoomed = false;
      _overlayPageController?.dispose();
      _overlayPageController = null;
      return false;
    }
    _flutterTts.stop();
    _scheduleReminderIfNeeded();
    return true;
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SETTINGS
  // ════════════════════════════════════════════════════════════════════════════

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFFBE6),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) =>
            Consumer<SettingsProvider>(
                builder: (context, settings, child) {
          final r = context.r;
          return SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.all(r.spacing(24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 50, height: 6,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                SizedBox(height: r.spacing(20)),

                Text("Tampilan & Font",
                    style: _comicNueBase.copyWith(
                        fontSize: r.font(22), color: Colors.orange[800])),
                SizedBox(height: r.spacing(12)),

                Text("Font Teks Bacaan:",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                        fontSize: r.font(14))),
                SizedBox(height: r.spacing(8)),

                Wrap(
                  spacing: r.spacing(8),
                  runSpacing: r.spacing(8),
                  children: _availableFonts.map((fontData) {
                    final fontName = fontData['name']!;
                    final fontLabel = fontData['label']!;
                    final isSelected = settings.fontFamily == fontName;
                    return GestureDetector(
                      onTap: () => settings.updateFontFamily(fontName),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(
                            horizontal: r.spacing(14), vertical: r.spacing(8)),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.orange : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? Colors.orange
                                : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                          boxShadow: isSelected
                              ? [BoxShadow(
                                  color: Colors.orange.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2))]
                              : [],
                        ),
                        child: Text(
                          fontLabel,
                          style: TextStyle(
                            fontFamily: fontName,
                            fontSize: r.font(13),
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                SizedBox(height: r.spacing(10)),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(r.spacing(12)),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Text(
                    'Contoh: Kancil pergi ke hutan.',
                    style: TextStyle(
                      fontFamily: settings.fontFamily,
                      fontSize: r.font(16),
                      color: Colors.black87,
                    ),
                  ),
                ),

                const Divider(height: 30),

                Text("Alat Bantu Baca",
                    style: _comicNueBase.copyWith(
                        fontSize: r.font(22), color: Colors.orange[800])),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text("Mode Eja (Be-la-jar)",
                      style: TextStyle(
                          fontFamily: settings.fontFamily,
                          fontWeight: FontWeight.bold)),
                  subtitle: const Text("Membantu mengeja kata"),
                  value: settings.enableSyllable,
                  onChanged: (val) => settings.toggleSyllable(val),
                  activeColor: Colors.orange,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text("Penggaris Fokus",
                      style: TextStyle(
                          fontFamily: settings.fontFamily,
                          fontWeight: FontWeight.bold)),
                  value: settings.enableRuler,
                  onChanged: (val) => settings.toggleRuler(val),
                  activeColor: Colors.orange,
                ),

                const Divider(height: 30),

                Text("Suara & Teks",
                    style: _comicNueBase.copyWith(
                        fontSize: r.font(22), color: Colors.orange[800])),
                SizedBox(height: r.spacing(10)),

                Text("Kecepatan Bicara: ${settings.ttsRate.toStringAsFixed(1)}x",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.orange)),
                SettingsSliderRow(
                  leftLabel: "Lambat", rightLabel: "Cepat",
                  child: Slider(
                    value: settings.ttsRate, min: 0.1, max: 1.0, divisions: 10,
                    activeColor: Colors.orange,
                    onChanged: (val) {
                      settings.updateTtsRate(val);
                      _flutterTts.setSpeechRate(val);
                    },
                  ),
                ),
                SizedBox(height: r.spacing(10)),

                Text("Ukuran Huruf: ${(settings.textScaleFactor * 100).toInt()}%",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.orange)),
                SettingsSliderRow(
                  leftLabel: "Kecil", rightLabel: "Besar",
                  child: Slider(
                    value: settings.textScaleFactor,
                    min: 0.8, max: 1.5, divisions: 7,
                    activeColor: Colors.orange,
                    onChanged: (val) => settings.updateTextScale(val),
                  ),
                ),
                SizedBox(height: r.spacing(10)),

                Text("Jarak Antar Huruf: ${settings.letterSpacing.toStringAsFixed(1)}",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.orange)),
                SettingsSliderRow(
                  leftLabel: "Rapat", rightLabel: "Lebar",
                  child: Slider(
                    value: settings.letterSpacing,
                    min: 0.0, max: 4.0, divisions: 8,
                    activeColor: Colors.orange,
                    onChanged: (val) => settings.updateLetterSpacing(val),
                  ),
                ),
                SizedBox(height: r.spacing(10)),

                Text("Jarak Antar Baris: ${settings.lineHeight.toStringAsFixed(1)}",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.orange)),
                SettingsSliderRow(
                  leftLabel: "Rapat", rightLabel: "Lebar",
                  child: Slider(
                    value: settings.lineHeight,
                    min: 1.2, max: 2.4, divisions: 6,
                    activeColor: Colors.orange,
                    onChanged: (val) => settings.updateLineHeight(val),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  void _showEditDialog(int index) {
    if (_isScreenLockedNotifier.value) return;
    _flutterTts.stop();
    _ttsStateNotifier.value = TtsState.paused;
    final controller = TextEditingController(text: _sentences[index]);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Edit Teks",
            style: _comicNueBase.copyWith(color: Colors.black87)),
        content: TextField(
          controller: controller, maxLines: 5,
          style: TextStyle(
              fontFamily: context.read<SettingsProvider>().fontFamily),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: "Perbaiki teks di sini...",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmDelete(index);
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context);
                _editSentenceAndSave(index, controller.text.trim());
              }
            },
            child: const Text("Simpan", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hapus?"),
        content: const Text("Paragraf ini akan dihapus permanen."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _deleteSentenceAndSave(index);
            },
            child: const Text("Hapus", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final r = context.r;
    final double progress = _pages.isEmpty
        ? 0
        : (_currentVisualPage + 1) / _pages.length;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: CircleButton(
            icon: Icons.arrow_back_rounded,
            onTap: () {
              if (_isPracticeModeNotifier.value) {
                _savePracticeProgress();
                _isPracticeModeNotifier.value = false;
                return;
              }
              if (_isShowingFullImageNotifier.value) {
                _isShowingFullImageNotifier.value = false;
                _isOverlayZoomed = false;
                _overlayPageController?.dispose();
                _overlayPageController = null;
              } else {
                _flutterTts.stop();
                _scheduleReminderIfNeeded();
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            ValueListenableBuilder<bool>(
              valueListenable: _isScreenLockedNotifier,
              builder: (context, isLocked, _) => CircleButton(
                icon: isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                color: isLocked ? Colors.red : Colors.black45,
                onTap: () => _isScreenLockedNotifier.value = !isLocked,
              ),
            ),
            const SizedBox(width: 8),
            CircleButton(
              icon: Icons.settings_rounded,
              onTap: () => _showSettings(context),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<String>(
                valueListenable: _currentImageUrlNotifier,
                builder: (context, url, _) {
                  if (url.isEmpty) return const SizedBox.shrink();
                  return Hero(
                    tag: 'cover_${widget.documentId.replaceAll("lib_", "")}',
                    child: RepaintBoundary(
                      child: url.startsWith('http')
                          ? CachedNetworkImage(
                              imageUrl: url, fit: BoxFit.cover,
                              color: _bgBlurOverlay,
                              colorBlendMode: BlendMode.darken,
                              imageBuilder: (ctx, provider) => ImageFiltered(
                                imageFilter: ImageFilter.blur(
                                    sigmaX: 15, sigmaY: 15),
                                child: Image(image: provider, fit: BoxFit.cover),
                              ),
                              placeholder: (_, __) => const SizedBox(),
                            )
                          : ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                  sigmaX: 15, sigmaY: 15),
                              child: Image.file(File(url),
                                  fit: BoxFit.cover,
                                  color: _bgBlurOverlay,
                                  colorBlendMode: BlendMode.darken),
                            ),
                    ),
                  );
                },
              ),
            ),
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                switchInCurve: Curves.easeIn,
                switchOutCurve: Curves.easeOut,
                child: _isLoadingText
                    ? const SizedBox.shrink(key: ValueKey('loading'))
                    : _buildListeningContent(context, settings, r, progress),
              ),
            ),
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: _isShowingFullImageNotifier,
                builder: (context, showing, _) {
                  if (!showing) return const SizedBox.shrink();
                  return _buildFullscreenImageOverlay(r);
                },
              ),
            ),
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: _isPracticeModeNotifier,
                builder: (context, isPractice, _) {
                  if (!isPractice) return const SizedBox.shrink();
                  return PracticeMicPanel(
                    onPracticeDone: _handlePracticeResult,
                    onCancel: _togglePracticeMode, // _togglePracticeMode sudah memanggil _savePracticeProgress() secara internal
                    onFinishAll: _handleFinishAll,
                    onNext: _practiceNext,
                    onPrev: _practicePrev,
                    activeSentenceText: _sentences.isNotEmpty
                        ? _sentences[_currentSentenceIndex]
                        : '',
                    currentSentenceIndex: _currentSentenceIndex,
                    totalSentences: _sentences.length,
                    lastEvaluationResult:
                        _evaluationResults[_currentSentenceIndex],
                    canGoPrev: _currentSentenceIndex > 0,
                    canGoNext: _currentSentenceIndex < _sentences.length - 1,
                    totalSentencesPracticed: _evaluationResults.length,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Konten halaman Mendengarkan ──────────────────────────────────────────
  Widget _buildListeningContent(
    BuildContext context,
    SettingsProvider settings,
    ResponsiveHelper r,
    double progress,
  ) {
    return Stack(
      key: const ValueKey('content'),
      children: [
        Column(
          children: [
            // Gambar
            Expanded(
              flex: 4,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  r.spacing(20), r.spacing(100),
                  r.spacing(20), r.spacing(20),
                ),
                child: ValueListenableBuilder<bool>(
                  valueListenable: _isScreenLockedNotifier,
                  builder: (context, isLocked, _) => PageView.builder(
                    controller: _imagePageController,
                    physics: isLocked
                        ? const NeverScrollableScrollPhysics()
                        : const BouncingScrollPhysics(),
                    onPageChanged: (idx) => _syncPages(idx, fromImage: true),
                    itemCount: _pages.length,
                    itemBuilder: (context, index) {
                      int imgIdx = _pages[index].isNotEmpty
                          ? (_sentenceToImageMap.isNotEmpty
                              ? _sentenceToImageMap[_pages[index].first]
                              : 0)
                          : 0;
                      final url = _displayImages.isNotEmpty
                          ? _displayImages[
                              min(imgIdx, _displayImages.length - 1)]
                          : "";
                      return GestureDetector(
                        onTap: () {
                          if (!isLocked) {
                            _overlayPageController = PageController(
                                initialPage: _currentVisualPage);
                            _isShowingFullImageNotifier.value = true;
                            _isOverlayZoomed = false;
                          }
                        },
                        child: ImageViewer(url: url, onLoaded: _onImageLoaded),
                      );
                    },
                  ),
                ),
              ),
            ),

            // Panel Teks
            Expanded(
              flex: 6,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFFFFBE6),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(30)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 20,
                        spreadRadius: 5)
                  ],
                ),
                child: Stack(
                  children: [
                    Column(
                      children: [
                        ReadingModeTabSwitcher(
                          isPracticeMode: _isPracticeModeNotifier,
                          currentPage: _currentVisualPage,
                          totalPages: _pages.length,
                          onToggle: _togglePracticeMode,
                          r: r,
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: r.spacing(24),
                            vertical: r.spacing(5),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: r.size(5),
                              backgroundColor: _progressBgColor,
                              valueColor: const AlwaysStoppedAnimation(
                                  Colors.orange),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _isScreenLockedNotifier,
                            builder: (context, isLocked, _) =>
                                PageView.builder(
                              controller: _textPageController,
                              physics: isLocked
                                  ? const NeverScrollableScrollPhysics()
                                  : const BouncingScrollPhysics(),
                              onPageChanged: (idx) =>
                                  _syncPages(idx, fromText: true),
                              itemCount: _pages.length,
                              itemBuilder: (context, pageIndex) =>
                                  SingleChildScrollView(
                                padding: EdgeInsets.fromLTRB(
                                  r.spacing(24), r.spacing(10),
                                  r.spacing(24), r.spacing(200),
                                ),
                                physics: const BouncingScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: _pages[pageIndex].map((idx) {
                                    if (!_itemKeys.containsKey(idx)) {
                                      _itemKeys[idx] = GlobalKey();
                                    }
                                    return InteractiveSentence(
                                      key: _itemKeys[idx],
                                      index: idx,
                                      normalText: _sentences[idx],
                                      syllableText:
                                          _syllabifiedSentences.length > idx
                                              ? _syllabifiedSentences[idx]
                                              : _sentences[idx],
                                      isActive: idx == _currentSentenceIndex,
                                      settings: settings,
                                      highlightNotifier: _highlightNotifier,
                                      onTap: () {
                                        if (!isLocked) {
                                          _flutterTts.stop();
                                          setState(() =>
                                              _currentSentenceIndex = idx);
                                          if (!_isPracticeModeNotifier.value) {
                                            _ttsStateNotifier.value =
                                                TtsState.playing;
                                            _checkAndSyncPageForward();
                                            _speakCurrentSentence();
                                          }
                                        }
                                      },
                                      onLongPress: () => _showEditDialog(idx),
                                      r: r,
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Kontrol TTS
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: r.spacing(16),
                            top: r.spacing(8),
                          ),
                          child: Center(
                            child: ValueListenableBuilder<TtsState>(
                              valueListenable: _ttsStateNotifier,
                              builder: (context, ttsState, _) =>
                                  ReaderControls(
                                isPlaying: ttsState == TtsState.playing,
                                isReady: _isTtsReady,
                                onPlayPause: _togglePlayPause,
                                onPrev: () {
                                  if (_currentSentenceIndex > 0) {
                                    _flutterTts.stop();
                                    setState(() => _currentSentenceIndex--);
                                    _checkAndSyncPageForward();
                                    if (ttsState == TtsState.playing) {
                                      _speakCurrentSentence();
                                    }
                                  }
                                },
                                onNext: () {
                                  if (_currentSentenceIndex <
                                      _sentences.length - 1) {
                                    _flutterTts.stop();
                                    setState(() => _currentSentenceIndex++);
                                    _checkAndSyncPageForward();
                                    if (ttsState == TtsState.playing) {
                                      _speakCurrentSentence();
                                    }
                                  }
                                },
                                r: r,
                              ),
                            ),
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

        if (settings.enableRuler)
          ReadingRuler(opacity: settings.rulerOpacity),
      ],
    );
  }

  // ── Fullscreen image overlay ──────────────────────────────────────────────
  Widget _buildFullscreenImageOverlay(ResponsiveHelper r) {
    return Container(
      color: _fullscreenBgColor,
      child: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _overlayPageController,
              physics: _isOverlayZoomed
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              onPageChanged: (idx) => _syncPages(idx, fromOverlay: true),
              itemCount: _pages.length,
              itemBuilder: (context, index) {
                int imgIdx = _pages[index].isNotEmpty
                    ? (_sentenceToImageMap.isNotEmpty
                        ? _sentenceToImageMap[_pages[index].first]
                        : 0)
                    : 0;
                final url = _displayImages.isNotEmpty
                    ? _displayImages[min(imgIdx, _displayImages.length - 1)]
                    : "";
                return ZoomableFullscreenImage(
                  key: ValueKey(index),
                  url: url,
                  onZoomChanged: (isZoomed) {
                    if (_isOverlayZoomed != isZoomed) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _isOverlayZoomed = isZoomed);
                      });
                    }
                  },
                );
              },
            ),
            Positioned(
              top: r.spacing(16),
              right: r.spacing(16),
              child: CircleAvatar(
                backgroundColor: Colors.white24,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    _isShowingFullImageNotifier.value = false;
                    _isOverlayZoomed = false;
                    _overlayPageController?.dispose();
                    _overlayPageController = null;
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}