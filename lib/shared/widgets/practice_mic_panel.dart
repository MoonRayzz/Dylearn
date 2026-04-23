// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/models/reading_session.dart';
import '../providers/settings_provider.dart';
import '../../core/services/stt_service.dart';
import '../../core/utils/reading_evaluator.dart';
import '../../core/utils/responsive_helper.dart';
import '../../core/utils/text_utils.dart';

// ══════════════════════════════════════════════════════════════════════════════
// PracticeMicPanel v3 — Mode Latihan Membaca Nyaring (Dyslexia-Friendly)
//
// Perubahan dari v2:
//   • dispose() → resetSession() agar singleton SttService tidak rusak
//   • withOpacity() → withValues(alpha:) (Flutter 3.27+ non-deprecated)
//   • _DetailStats di-cache saat evaluasi berubah, bukan hitung ulang tiap rebuild
// ══════════════════════════════════════════════════════════════════════════════

// ── Cache model untuk stats detail ───────────────────────────────────────────
class _DetailStats {
  final int correct;
  final int partial;
  final int wrong;
  const _DetailStats(this.correct, this.partial, this.wrong);

  static _DetailStats from(List<WordEvaluation> evals) {
    int c = 0, p = 0, w = 0;
    for (final e in evals) {
      switch (e.status) {
        case WordStatus.correct:           c++; break;
        case WordStatus.partially_correct: p++; break;
        case WordStatus.incorrect:
        case WordStatus.missed:            w++; break;
      }
    }
    return _DetailStats(c, p, w);
  }
}

// ── Model word chip untuk feedback panel ─────────────────────────────────────
class _FeedbackWord {
  final String word;
  final WordStatus status;
  const _FeedbackWord(this.word, this.status);
}

class PracticeMicPanel extends StatefulWidget {
  final Future<void> Function(String recognizedText) onPracticeDone;
  final VoidCallback onCancel;
  final VoidCallback onFinishAll;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final String activeSentenceText;
  final int currentSentenceIndex;
  final int totalSentences;
  final List<WordEvaluation>? lastEvaluationResult;
  final bool canGoPrev;
  final bool canGoNext;
  final int totalSentencesPracticed;

  const PracticeMicPanel({
    super.key,
    required this.onPracticeDone,
    required this.onCancel,
    required this.onFinishAll,
    required this.onNext,
    required this.onPrev,
    required this.activeSentenceText,
    required this.currentSentenceIndex,
    required this.totalSentences,
    this.lastEvaluationResult,
    this.canGoPrev = false,
    this.canGoNext = false,
    this.totalSentencesPracticed = 0,
  });

  @override
  State<PracticeMicPanel> createState() => _PracticeMicPanelState();
}

class _PracticeMicPanelState extends State<PracticeMicPanel>
    with SingleTickerProviderStateMixin {
  final SttService _sttService = SttService();
  final FlutterTts _flutterTts = FlutterTts();
  final ValueNotifier<bool> _isTtsPlayingNotifier = ValueNotifier(false);
  final ValueNotifier<TextRange?> _ttsHighlightNotifier = ValueNotifier(null);

  // Opsi A: Feedback word chip panel
  // Notifier kata mana yang sedang dibaca TTS feedback (berdasarkan teks kata)
  final ValueNotifier<String?> _feedbackHighlightWord = ValueNotifier(null);
  // Flag: true saat TTS feedback aktif, false saat TTS kalimat biasa
  bool _isFeedbackTtsActive = false;
  // Daftar kata bermasalah yang ditampilkan di feedback panel
  List<_FeedbackWord> _cachedFeedbackWords = [];

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  bool _showResult = false;
  bool _showDetail = false;
  double _lastAccuracy = 0.0;

  // FIX Isu 3: cache stats — dihitung SEKALI saat evaluasi berubah,
  // tidak diulang setiap setState() (animasi mic, toggle detail, dsb.)
  _DetailStats? _cachedStats;

  // Timer untuk delay sebelum TTS feedback otomatis diputar
  Timer? _feedbackTimer;

  // ── Tema warna ────────────────────────────────────────────────────────────
  static const Color _bgTop       = Color(0xFFFFF8E1);
  static const Color _bgBottom    = Color(0xFFFFF3E0);
  static const Color _accent      = Color(0xFFE65100);
  static const Color _textPrimary = Color(0xFF1A237E);
  static const Color _textBody    = Color(0xFF3E2723);

  static const Color _micActive = Color(0xFFC62828);
  static const Color _micIdle   = Color(0xFFE65100);

  static const Color _successColor = Color(0xFF2E7D32);
  static const Color _warningColor = Color(0xFFF57F17);

  static const Color _evalCorrect = Color(0xFF2E7D32);
  static const Color _evalPartial = Color(0xFFF57F17);
  static const Color _evalWrong   = Color(0xFFC62828);

  static const Color _sylColorA = Color(0xFF6A1B9A);
  static const Color _sylColorB = Color(0xFF006064);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _sttService.isListeningNotifier.addListener(_onListeningChanged);
    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        _isTtsPlayingNotifier.value = false;
        _ttsHighlightNotifier.value = null;
        // Reset feedback chip highlight
        _feedbackHighlightWord.value = null;
        _isFeedbackTtsActive = false;
      }
    });
    _flutterTts.setErrorHandler((_) {
      if (mounted) {
        _isTtsPlayingNotifier.value = false;
        _ttsHighlightNotifier.value = null;
        _feedbackHighlightWord.value = null;
        _isFeedbackTtsActive = false;
      }
    });
    _flutterTts.setProgressHandler((text, start, end, word) {
      if (!mounted) return;
      if (_isFeedbackTtsActive) {
        // Mode feedback: highlight chip kata yang sedang dibaca
        // Normalisasi kata (lowercase, trim) agar cocok dengan chip
        final normalized = word.toLowerCase().trim();
        _feedbackHighlightWord.value = normalized;
      } else {
        // Mode kalimat biasa: highlight karakter di teks kalimat
        _ttsHighlightNotifier.value = TextRange(start: start, end: end);
      }
    });
    _syncResult();
  }

  @override
  void didUpdateWidget(PracticeMicPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentSentenceIndex != oldWidget.currentSentenceIndex) {
      // Ganti kalimat: batalkan feedback yang sedang/akan diputar
      _feedbackTimer?.cancel();
      _flutterTts.stop();
      _isTtsPlayingNotifier.value = false;
      _ttsHighlightNotifier.value = null;
      _feedbackHighlightWord.value = null;
      _isFeedbackTtsActive = false;
      _cachedFeedbackWords = [];
      _sttService.recognizedTextNotifier.value = '';
      _sttService.errorNotifier.value = '';
      _showDetail = false;
      _syncResult();
    } else if (widget.lastEvaluationResult != oldWidget.lastEvaluationResult) {
      _showDetail = false;
      _syncResult();
    }
  }

  void _syncResult() {
    final evals = widget.lastEvaluationResult;
    if (evals != null && evals.isNotEmpty) {
      _lastAccuracy = ReadingEvaluator.calculateOverallAccuracy(evals);
      // FIX Isu 3: hitung stats sekali di sini, bukan di _buildDetailStats
      _cachedStats = _DetailStats.from(evals);

      // Bangun cache feedback words untuk panel chip
      _cachedFeedbackWords = _buildFeedbackWordList(evals);

      if (mounted) setState(() => _showResult = true);

      // Jadwalkan TTS feedback dengan delay 1.2 detik agar tidak mengagetkan
      _feedbackTimer?.cancel();
      _feedbackTimer = Timer(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        final settings = context.read<SettingsProvider>();
        if (settings.enableFeedbackTts) {
          _speakFeedback(evals, settings);
        }
      });
    } else {
      _cachedStats = null;
      _cachedFeedbackWords = [];
      _feedbackTimer?.cancel();
      if (mounted) setState(() => _showResult = false);
    }
  }

  /// Bangun daftar kata bermasalah dari hasil evaluasi (urut sesuai posisi kalimat).
  List<_FeedbackWord> _buildFeedbackWordList(List<WordEvaluation> evals) {
    final result = <_FeedbackWord>[];
    for (final e in evals) {
      final word = e.originalWord.trim();
      if (word.isEmpty) continue;
      if (e.status == WordStatus.incorrect ||
          e.status == WordStatus.partially_correct ||
          e.status == WordStatus.missed) {
        result.add(_FeedbackWord(word, e.status));
      }
    }
    return result;
  }

  // ── TTS Feedback Otomatis ─────────────────────────────────────────────────

  /// Membangun dan memutar kalimat feedback TTS setelah evaluasi.
  /// Urutan: pujian → kata salah/kurang tepat → kata terlewat.
  /// Highlight diarahkan ke chip panel — BUKAN ke kalimat utama.
  Future<void> _speakFeedback(
    List<WordEvaluation> evals,
    SettingsProvider settings,
  ) async {
    // Jangan putar jika TTS sedang berjalan
    if (_isTtsPlayingNotifier.value) return;

    // Pisahkan kata bermasalah berdasarkan status
    final wrongOrPartial = <String>[];
    final missed = <String>[];

    for (final e in evals) {
      final word = e.originalWord.trim();
      if (word.isEmpty) continue;
      switch (e.status) {
        case WordStatus.incorrect:
        case WordStatus.partially_correct:
          wrongOrPartial.add(word);
          break;
        case WordStatus.missed:
          missed.add(word);
          break;
        case WordStatus.correct:
          break;
      }
    }

    // ── Bangun kalimat feedback ────────────────────────────────────────────
    final buffer = StringBuffer();

    // 1. Pujian berdasarkan akurasi (selalu disampaikan)
    if (_lastAccuracy >= 90) {
      buffer.write('Luar biasa! Bacaanmu hampir sempurna! ');
    } else if (_lastAccuracy >= 75) {
      buffer.write('Hebat! Kamu sudah membaca dengan baik! ');
    } else if (_lastAccuracy >= 55) {
      buffer.write('Bagus! Terus semangat berlatih! ');
    } else if (_lastAccuracy >= 35) {
      buffer.write('Jangan menyerah, kamu pasti bisa! ');
    } else {
      buffer.write('Coba dengarkan dulu, lalu baca lagi! ');
    }

    // 2. Kata salah / kurang tepat
    if (wrongOrPartial.isNotEmpty) {
      buffer.write('Perhatikan kata-kata ini ya: ');
      buffer.write(wrongOrPartial.join(', '));
      buffer.write('. ');
    }

    // 3. Kata terlewat
    if (missed.isNotEmpty) {
      if (missed.length == 1) {
        buffer.write('Ada satu kata yang kamu lewati: ${missed[0]}. Coba ucapkan lagi ya!');
      } else {
        buffer.write('Ada kata yang kamu lewati: ');
        buffer.write(missed.join(', '));
        buffer.write('. Coba ucapkan lagi ya!');
      }
    }

    final feedbackText = buffer.toString().trim();
    if (feedbackText.isEmpty) return;

    try {
      await _flutterTts.setLanguage('id-ID');
      // Feedback sedikit lebih lambat agar anak tidak ketinggalan
      await _flutterTts.setSpeechRate(
          (settings.ttsRate * 0.9).clamp(0.1, 1.0));
      await _flutterTts.setPitch(settings.ttsPitch);
      if (settings.selectedVoice != null) {
        await _flutterTts.setVoice(settings.selectedVoice!);
      }
      // Aktifkan mode feedback — progress handler akan routing ke chip notifier
      _isFeedbackTtsActive = true;
      _isTtsPlayingNotifier.value = true;
      await _flutterTts.speak(feedbackText);
    } catch (_) {
      if (mounted) {
        _isTtsPlayingNotifier.value = false;
        _isFeedbackTtsActive = false;
      }
    }
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _pulseController.dispose();
    _flutterTts.stop();
    _isTtsPlayingNotifier.dispose();
    _ttsHighlightNotifier.dispose();
    _feedbackHighlightWord.dispose();
    _sttService.isListeningNotifier.removeListener(_onListeningChanged);

    // FIX Isu 1: resetSession() — bersihkan state sesi tanpa merusak singleton.
    // JANGAN panggil _sttService.dispose() atau _sttService.disposeForAppExit()
    // dari widget — itu hanya untuk app exit.
    _sttService.resetSession();
    super.dispose();
  }

  void _onListeningChanged() {
    final isListening = _sttService.isListeningNotifier.value;
    if (isListening) {
      if (mounted) setState(() => _showResult = false);
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController
        ..stop()
        ..reset();
      Future.microtask(() async {
        if (!mounted) return;
        final text = _sttService.recognizedTextNotifier.value.trim();
        if (text.isNotEmpty) await widget.onPracticeDone(text);
      });
    }
  }

  void _toggleListening() {
    if (_sttService.isListeningNotifier.value) {
      _sttService.stopListening();
    } else {
      // User mulai rekam: batalkan semua TTS yang sedang berjalan
      _feedbackTimer?.cancel();
      _flutterTts.stop();
      _isTtsPlayingNotifier.value = false;
      _ttsHighlightNotifier.value = null;
      _feedbackHighlightWord.value = null;
      _isFeedbackTtsActive = false;
      _sttService.startListening();
    }
  }

  Future<void> _speakSentence(SettingsProvider settings) async {
    if (_isTtsPlayingNotifier.value) {
      await _flutterTts.stop();
      _isTtsPlayingNotifier.value = false;
      _ttsHighlightNotifier.value = null;
      return;
    }
    try {
      await _flutterTts.setLanguage('id-ID');
      await _flutterTts.setSpeechRate(settings.ttsRate);
      await _flutterTts.setPitch(settings.ttsPitch);
      if (settings.selectedVoice != null) {
        await _flutterTts.setVoice(settings.selectedVoice!);
      }
      _isTtsPlayingNotifier.value = true;
      await _flutterTts.speak(widget.activeSentenceText);
    } catch (_) {
      if (mounted) _isTtsPlayingNotifier.value = false;
    }
  }

  // ── Score helpers ─────────────────────────────────────────────────────────
  Color _scoreColor(double s) =>
      s >= 80 ? _successColor : (s >= 50 ? _warningColor : Colors.red.shade700);

  String _scoreEmoji(double s) =>
      s >= 90 ? '🌟' : (s >= 75 ? '👍' : (s >= 55 ? '💪' : (s >= 35 ? '🔄' : '👂')));

  String _scoreMsg(double s) {
    if (s >= 90) return 'Luar Biasa! Bacaanmu Sempurna!';
    if (s >= 75) return 'Hebat! Kamu Sudah Membaca dengan Baik!';
    if (s >= 55) return 'Bagus! Terus Semangat Berlatih!';
    if (s >= 35) return 'Jangan Menyerah, Kamu Pasti Bisa!';
    return 'Coba Dengarkan Dulu, Lalu Baca Lagi!';
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final r = ResponsiveHelper(context);
    final settings = context.watch<SettingsProvider>();

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bgTop, _bgBottom],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(r),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: r.spacing(20),
                    vertical: r.spacing(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildSentenceCard(r, settings),
                      SizedBox(height: r.spacing(16)),

                      ValueListenableBuilder<bool>(
                        valueListenable: _isTtsPlayingNotifier,
                        builder: (context, isPlaying, _) => AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: isPlaying
                              ? _TtsBadge(
                                  r: r,
                                  isFeedbackMode: _isFeedbackTtsActive,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),

                      SizedBox(height: r.spacing(8)),

                      ValueListenableBuilder<bool>(
                        valueListenable: _sttService.isListeningNotifier,
                        builder: (context, isListening, _) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildMicButton(isListening, r),
                            SizedBox(height: r.spacing(14)),
                            _buildStatusText(isListening, r),
                            if (_showResult && !isListening) ...[
                              SizedBox(height: r.spacing(12)),
                              _buildResultCard(r),
                              // Opsi A: Feedback word chip panel
                              if (_cachedFeedbackWords.isNotEmpty) ...[
                                SizedBox(height: r.spacing(12)),
                                _buildFeedbackWordPanel(r),
                              ],
                            ],
                          ],
                        ),
                      ),

                      ValueListenableBuilder<String>(
                        valueListenable: _sttService.errorNotifier,
                        builder: (context, err, _) {
                          if (err.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: EdgeInsets.only(top: r.spacing(10)),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: r.spacing(16),
                                vertical: r.spacing(8),
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Text(
                                '⚠️ $err',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.comicNeue(
                                  fontSize: r.font(12),
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      SizedBox(height: r.spacing(24)),
                    ],
                  ),
                ),
              ),
              _buildFooter(r),
            ],
          ),
        ),
      ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  Widget _buildTopBar(ResponsiveHelper r) => Container(
        padding: EdgeInsets.fromLTRB(
            r.spacing(16), r.spacing(12), r.spacing(16), r.spacing(10)),
        decoration: BoxDecoration(
          // FIX Isu 2: withValues(alpha:) menggantikan withOpacity()
          color: _accent.withValues(alpha: 0.07),
          border: Border(bottom: BorderSide(color: _accent.withValues(alpha: 0.15))),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: r.spacing(12), vertical: r.spacing(6)),
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.school_rounded, color: Colors.white, size: r.size(14)),
                  SizedBox(width: r.spacing(5)),
                  Text(
                    'MODE LATIHAN',
                    style: GoogleFonts.comicNeue(
                      fontSize: r.font(11),
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: r.spacing(10)),
            if (widget.totalSentences > 0)
              Expanded(
                child: Text(
                  'Kalimat ${widget.currentSentenceIndex + 1} / ${widget.totalSentences}',
                  style: GoogleFonts.comicNeue(
                    fontSize: r.font(12),
                    color: _textPrimary.withValues(alpha: 0.65),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              const Expanded(child: SizedBox()),
            GestureDetector(
              onTap: widget.onCancel,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: r.spacing(12), vertical: r.spacing(8)),
                decoration: BoxDecoration(
                  color: _textPrimary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _textPrimary.withValues(alpha: 0.15)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.volume_up_rounded,
                        color: _textPrimary.withValues(alpha: 0.65),
                        size: r.size(14)),
                    SizedBox(width: r.spacing(5)),
                    Text(
                      'Dengarkan',
                      style: GoogleFonts.comicNeue(
                        fontSize: r.font(11),
                        fontWeight: FontWeight.w900,
                        color: _textPrimary.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  // ── Sentence card ──────────────────────────────────────────────────────────
  Widget _buildSentenceCard(ResponsiveHelper r, SettingsProvider settings) {
    final borderColor = _showResult
        ? _scoreColor(_lastAccuracy).withValues(alpha: 0.45)
        : _accent.withValues(alpha: 0.3);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      constraints: BoxConstraints(minHeight: r.size(100)),
      padding: EdgeInsets.all(r.spacing(20)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _showResult ? Icons.fact_check_rounded : Icons.menu_book_rounded,
                color: _showResult ? _scoreColor(_lastAccuracy) : _accent,
                size: r.size(15),
              ),
              SizedBox(width: r.spacing(6)),
              Text(
                _showResult ? 'Hasil bacaanmu:' : 'Bacalah kalimat ini:',
                style: GoogleFonts.comicNeue(
                  fontSize: r.font(11),
                  color: _showResult ? _scoreColor(_lastAccuracy) : _accent,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          SizedBox(height: r.spacing(12)),

          ValueListenableBuilder<TextRange?>(
            valueListenable: _ttsHighlightNotifier,
            builder: (context, highlight, _) {
              if (_showResult && widget.lastEvaluationResult != null) {
                return _buildEvaluatedText(
                    widget.activeSentenceText,
                    widget.lastEvaluationResult!,
                    highlight, settings, r);
              }
              return _buildTtsHighlightedText(
                  widget.activeSentenceText, highlight, settings, r);
            },
          ),

          SizedBox(height: r.spacing(14)),

          ValueListenableBuilder<bool>(
            valueListenable: _isTtsPlayingNotifier,
            builder: (context, isPlaying, _) => InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: () => _speakSentence(settings),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(
                    horizontal: r.spacing(16), vertical: r.spacing(9)),
                decoration: BoxDecoration(
                  color: isPlaying
                      ? Colors.blue.shade50
                      : _accent.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isPlaying
                        ? Colors.blue.shade300
                        : _accent.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPlaying
                          ? Icons.stop_circle_rounded
                          : Icons.volume_up_rounded,
                      color: isPlaying ? Colors.blue.shade700 : _accent,
                      size: r.size(16),
                    ),
                    SizedBox(width: r.spacing(7)),
                    Text(
                      isPlaying ? 'Stop' : 'Dengarkan Teks',
                      style: GoogleFonts.comicNeue(
                        fontSize: r.font(12),
                        fontWeight: FontWeight.w900,
                        color: isPlaying ? Colors.blue.shade700 : _accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TEXT RENDERING
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildTtsHighlightedText(
    String text, TextRange? highlight, SettingsProvider settings, ResponsiveHelper r,
  ) {
    final TextStyle base = TextStyle(
      fontFamily: settings.fontFamily,
      fontSize: r.font(20) * settings.textScaleFactor,
      letterSpacing: settings.letterSpacing,
      height: settings.lineHeight,
      color: _textPrimary,
      fontWeight: FontWeight.bold,
    );
    if (!settings.enableSyllable && highlight == null) return Text(text, style: base);

    final segments  = TextUtils.tokenizeWords(text);
    final spans     = <InlineSpan>[];
    int   charOffset = 0;

    for (final seg in segments) {
      final segStart    = charOffset;
      final segEnd      = charOffset + seg.raw.length;
      final isTtsActive = highlight != null &&
          seg.isWord && highlight.start < segEnd && highlight.end > segStart;

      if (!seg.isWord) {
        spans.add(TextSpan(text: seg.raw, style: base));
        charOffset = segEnd;
        continue;
      }

      final wordSpans = _buildWordSpans(seg, base, _textPrimary, settings,
          useSyllableColors: true);
      spans.add(isTtsActive ? _ttsActiveSpan(wordSpans, base) : TextSpan(children: wordSpans));
      charOffset = segEnd;
    }
    return RichText(text: TextSpan(style: base, children: spans));
  }

  Widget _buildEvaluatedText(
    String text, List<WordEvaluation> evals, TextRange? highlight,
    SettingsProvider settings, ResponsiveHelper r,
  ) {
    final TextStyle base = TextStyle(
      fontFamily: settings.fontFamily,
      fontSize: r.font(20) * settings.textScaleFactor,
      letterSpacing: settings.letterSpacing,
      height: settings.lineHeight,
      fontWeight: FontWeight.bold,
    );

    final segments  = TextUtils.tokenizeWords(text);
    final spans     = <InlineSpan>[];
    int   evalIndex  = 0;
    int   charOffset = 0;

    for (final seg in segments) {
      final segStart = charOffset;
      final segEnd   = charOffset + seg.raw.length;

      if (!seg.isWord) {
        spans.add(TextSpan(text: seg.raw, style: base.copyWith(color: _textBody)));
        charOffset = segEnd;
        continue;
      }

      Color wordColor = _textBody;
      if (evalIndex < evals.length) {
        wordColor = _evalColorFor(evals[evalIndex].status);
        evalIndex++;
      }

      final wordStyle    = base.copyWith(color: wordColor);
      final isTtsActive  = highlight != null &&
          highlight.start < segEnd && highlight.end > segStart;
      final wordSpans    = _buildWordSpans(seg, wordStyle, wordColor, settings);

      spans.add(isTtsActive
          ? _ttsActiveSpanColored(wordSpans, wordColor, base)
          : TextSpan(children: wordSpans));
      charOffset = segEnd;
    }

    return RichText(
        text: TextSpan(style: base.copyWith(color: _textBody), children: spans));
  }

  Color _evalColorFor(WordStatus status) {
    switch (status) {
      case WordStatus.correct:           return _evalCorrect;
      case WordStatus.partially_correct: return _evalPartial;
      case WordStatus.incorrect:
      case WordStatus.missed:            return _evalWrong;
    }
  }

  List<InlineSpan> _buildWordSpans(
    dynamic seg, TextStyle base, Color color, SettingsProvider settings, {
    bool useSyllableColors = false,
  }) {
    if (settings.enableSyllable && seg.syllables.isNotEmpty) {
      int sylIdx = 0;
      return seg.syllables.map<InlineSpan>((syl) {
        final sylColor = useSyllableColors
            ? (sylIdx % 2 == 0 ? _sylColorA : _sylColorB)
            : color;
        sylIdx++;
        return TextSpan(text: syl.text, style: base.copyWith(color: sylColor));
      }).toList();
    }
    return [TextSpan(text: seg.raw, style: base.copyWith(color: color))];
  }

  WidgetSpan _ttsActiveSpan(List<InlineSpan> wordSpans, TextStyle base) =>
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: RichText(text: TextSpan(style: base, children: wordSpans)),
        ),
      );

  WidgetSpan _ttsActiveSpanColored(
      List<InlineSpan> wordSpans, Color evalColor, TextStyle base) =>
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: evalColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: RichText(text: TextSpan(style: base, children: wordSpans)),
        ),
      );

  // ══════════════════════════════════════════════════════════════════════════
  // MIC BUTTON
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildMicButton(bool isListening, ResponsiveHelper r) =>
      AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            if (isListening) ...[
              Transform.scale(
                scale: _pulseAnimation.value * 1.45,
                child: Container(
                  width: r.size(80), height: r.size(80),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _micActive.withValues(alpha: 0.12),
                  ),
                ),
              ),
              Transform.scale(
                scale: _pulseAnimation.value * 1.25,
                child: Container(
                  width: r.size(80), height: r.size(80),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _micActive.withValues(alpha: 0.22),
                  ),
                ),
              ),
            ],
            GestureDetector(
              onTap: _toggleListening,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: EdgeInsets.all(r.spacing(22)),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: isListening
                        ? [_micActive, _micActive.withValues(alpha: 0.80)]
                        : [_micIdle,   _micIdle.withValues(alpha: 0.80)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isListening ? _micActive : _micIdle)
                          .withValues(alpha: 0.4),
                      blurRadius: isListening ? 28 : 14,
                      spreadRadius: isListening ? 4 : 0,
                    ),
                  ],
                ),
                child: Icon(
                  isListening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white, size: r.size(44),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildStatusText(bool isListening, ResponsiveHelper r) {
    if (_showResult && !isListening) return const SizedBox.shrink();
    return isListening
        ? ValueListenableBuilder<String>(
            valueListenable: _sttService.recognizedTextNotifier,
            builder: (context, text, _) => Text(
              text.isEmpty ? '🎙️ Mendengarkan...' : '"$text"',
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.comicNeue(
                fontSize: r.font(14),
                color: _accent,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        : Text(
            'Tekan tombol & baca dengan lantang! 😊',
            textAlign: TextAlign.center,
            style: GoogleFonts.comicNeue(
              fontSize: r.font(13),
              color: _textPrimary.withValues(alpha: 0.65),
              fontWeight: FontWeight.bold,
            ),
          );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // RESULT CARD
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildResultCard(ResponsiveHelper r) {
    final color = _scoreColor(_lastAccuracy);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: EdgeInsets.all(r.spacing(16)),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(_scoreEmoji(_lastAccuracy),
                  style: TextStyle(fontSize: r.font(32))),
              SizedBox(width: r.spacing(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_lastAccuracy.toStringAsFixed(0)}%',
                      style: GoogleFonts.comicNeue(
                        fontSize: r.font(36),
                        fontWeight: FontWeight.w900,
                        color: color,
                        height: 1,
                      ),
                    ),
                    SizedBox(height: r.spacing(2)),
                    Text(
                      _scoreMsg(_lastAccuracy),
                      style: GoogleFonts.comicNeue(
                        fontSize: r.font(12),
                        color: color.withValues(alpha: 0.85),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: r.spacing(12)),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.refresh_rounded,
                  label: 'Coba Lagi',
                  onTap: () {
                    setState(() { _showResult = false; _showDetail = false; });
                    _sttService.recognizedTextNotifier.value = '';
                    _sttService.errorNotifier.value = '';
                  },
                  r: r,
                  textColor: _textPrimary.withValues(alpha: 0.7),
                  borderColor: Colors.grey.shade300,
                ),
              ),
              SizedBox(width: r.spacing(10)),
              Expanded(
                child: _ActionButton(
                  icon: _showDetail
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.bar_chart_rounded,
                  label: _showDetail ? 'Sembunyikan' : 'Lihat Detail',
                  onTap: () => setState(() => _showDetail = !_showDetail),
                  r: r,
                  textColor: _showDetail ? color : _textPrimary.withValues(alpha: 0.7),
                  borderColor: _showDetail
                      ? color.withValues(alpha: 0.4)
                      : Colors.grey.shade300,
                  bgColor: _showDetail ? color.withValues(alpha: 0.08) : null,
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _showDetail && _cachedStats != null
                ? Padding(
                    padding: EdgeInsets.only(top: r.spacing(14)),
                    child: _buildDetailStats(r, _cachedStats!),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // FIX Isu 3: terima _DetailStats yang sudah di-cache — tidak ada loop di sini
  Widget _buildDetailStats(ResponsiveHelper r, _DetailStats stats) {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: r.spacing(12),
          runSpacing: r.spacing(6),
          children: [
            _ColorLegend(color: _evalCorrect, label: '✅ Benar', r: r),
            _ColorLegend(color: _evalPartial, label: '🟡 Kurang Tepat', r: r),
            _ColorLegend(color: _evalWrong,   label: '❌ Salah/Lewat', r: r),
          ],
        ),
        SizedBox(height: r.spacing(12)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _StatChip(emoji: '✅', count: stats.correct, label: 'Benar',
                color: _successColor, r: r),
            Container(width: 1, height: 36, color: Colors.grey.shade300),
            _StatChip(emoji: '🟡', count: stats.partial, label: 'Kurang',
                color: _warningColor, r: r),
            Container(width: 1, height: 36, color: Colors.grey.shade300),
            _StatChip(emoji: '❌', count: stats.wrong, label: 'Salah',
                color: _evalWrong, r: r),
          ],
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FEEDBACK WORD CHIP PANEL (Opsi A)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildFeedbackWordPanel(ResponsiveHelper r) {
    return ValueListenableBuilder<String?>(
      valueListenable: _feedbackHighlightWord,
      builder: (context, activeWord, _) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          padding: EdgeInsets.all(r.spacing(14)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _isFeedbackTtsActive
                  ? Colors.deepOrange.shade200
                  : Colors.grey.shade200,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header panel
              Row(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: _isTtsPlayingNotifier,
                    builder: (_, playing, __) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: playing && _isFeedbackTtsActive
                          ? Row(
                              key: const ValueKey('playing'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.volume_up_rounded,
                                    size: r.size(14),
                                    color: Colors.deepOrange.shade600),
                                SizedBox(width: r.spacing(5)),
                                Text(
                                  'Yuk perhatikan kata-kata ini:',
                                  style: GoogleFonts.comicNeue(
                                    fontSize: r.font(11),
                                    fontWeight: FontWeight.w900,
                                    color: Colors.deepOrange.shade700,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              key: const ValueKey('idle'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    size: r.size(14),
                                    color: Colors.grey.shade600),
                                SizedBox(width: r.spacing(5)),
                                Text(
                                  'Kata yang perlu diperhatikan:',
                                  style: GoogleFonts.comicNeue(
                                    fontSize: r.font(11),
                                    fontWeight: FontWeight.w900,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: r.spacing(10)),

              // Chips kata bermasalah
              Wrap(
                spacing: r.spacing(8),
                runSpacing: r.spacing(8),
                children: _cachedFeedbackWords.map((fw) {
                  final isActive = activeWord != null &&
                      fw.word.toLowerCase() == activeWord;
                  return _FeedbackWordChip(
                    feedbackWord: fw,
                    isActive: isActive,
                    r: r,
                    evalWrong: _evalWrong,
                    evalPartial: _evalPartial,
                  );
                }).toList(),
              ),

              // Legenda
              SizedBox(height: r.spacing(10)),
              Wrap(
                spacing: r.spacing(12),
                children: [
                  _MiniLegend(color: _evalWrong,   emoji: '❌', label: 'Salah', r: r),
                  _MiniLegend(color: _evalPartial, emoji: '🟡', label: 'Kurang Tepat', r: r),
                  _MiniLegend(color: Colors.blueGrey.shade400, emoji: '⚪', label: 'Terlewat', r: r),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FOOTER
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildFooter(ResponsiveHelper r) {
    final bool canFinish = widget.totalSentencesPracticed > 0 || _showResult;
    return Container(
      padding: EdgeInsets.fromLTRB(
          r.spacing(16), r.spacing(12), r.spacing(16), r.spacing(16)),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _NavButton(icon: Icons.arrow_back_ios_rounded, label: 'Sebelumnya',
                    enabled: widget.canGoPrev, onTap: widget.onPrev, r: r),
                if (widget.totalSentences > 1 && widget.totalSentences <= 10)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(widget.totalSentences, (i) =>
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: EdgeInsets.symmetric(horizontal: r.spacing(2)),
                        width: i == widget.currentSentenceIndex ? r.size(14) : r.size(5),
                        height: r.size(5),
                        decoration: BoxDecoration(
                          color: i == widget.currentSentenceIndex
                              ? _accent : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    '${widget.currentSentenceIndex + 1} / ${widget.totalSentences}',
                    style: GoogleFonts.comicNeue(
                      fontSize: r.font(12),
                      color: _textPrimary.withValues(alpha: 0.55),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                _NavButton(icon: Icons.arrow_forward_ios_rounded, label: 'Berikutnya',
                    enabled: widget.canGoNext, onTap: widget.onNext, r: r,
                    isNext: true),
              ],
            ),
            SizedBox(height: r.spacing(12)),
            AnimatedOpacity(
              opacity: canFinish ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 300),
              child: GestureDetector(
                onTap: canFinish ? widget.onFinishAll : null,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: r.spacing(13)),
                  decoration: BoxDecoration(
                    color: canFinish ? _accent : Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: canFinish
                        ? [BoxShadow(
                            color: _accent.withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          )]
                        : [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flag_rounded, color: Colors.white, size: r.size(18)),
                      SizedBox(width: r.spacing(7)),
                      Flexible(
                        child: Text(
                          canFinish
                              ? 'Selesai Latihan & Lihat Rekap'
                              : 'Latih minimal 1 kalimat dulu 😊',
                          style: GoogleFonts.comicNeue(
                            fontSize: r.font(14),
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Widget pembantu (tidak berubah secara logika, hanya withValues)
// ══════════════════════════════════════════════════════════════════════════════

class _TtsBadge extends StatelessWidget {
  final ResponsiveHelper r;
  final bool isFeedbackMode;
  const _TtsBadge({required this.r, this.isFeedbackMode = false});
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
            horizontal: r.spacing(14), vertical: r.spacing(6)),
        decoration: BoxDecoration(
          color: isFeedbackMode
              ? Colors.deepOrange.shade50
              : Colors.blue.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isFeedbackMode
                ? Colors.deepOrange.shade200
                : Colors.blue.shade200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.volume_up_rounded,
              color: isFeedbackMode
                  ? Colors.deepOrange.shade700
                  : Colors.blue.shade700,
              size: r.size(13),
            ),
            SizedBox(width: r.spacing(5)),
            Text(
              isFeedbackMode ? '🎧 Membacakan feedback...' : '🔊 Memutar kalimat...',
              style: GoogleFonts.comicNeue(
                fontSize: r.font(11),
                fontWeight: FontWeight.w900,
                color: isFeedbackMode
                    ? Colors.deepOrange.shade700
                    : Colors.blue.shade700,
              ),
            ),
          ],
        ),
      );
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ResponsiveHelper r;
  final Color textColor;
  final Color borderColor;
  final Color? bgColor;
  const _ActionButton({
    required this.icon, required this.label, required this.onTap,
    required this.r, required this.textColor, required this.borderColor,
    this.bgColor,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: r.spacing(12), vertical: r.spacing(10)),
          decoration: BoxDecoration(
            color: bgColor ?? Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: textColor, size: r.size(14)),
              SizedBox(width: r.spacing(5)),
              Text(label, style: GoogleFonts.comicNeue(
                fontSize: r.font(12), fontWeight: FontWeight.w900, color: textColor)),
            ],
          ),
        ),
      );
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final ResponsiveHelper r;
  final bool isNext;

  static const Color _accent      = Color(0xFFE65100);
  static const Color _textPrimary = Color(0xFF1A237E);

  const _NavButton({
    required this.icon, required this.label, required this.enabled,
    required this.onTap, required this.r, this.isNext = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
              horizontal: r.spacing(12), vertical: r.spacing(8)),
          decoration: BoxDecoration(
            color: enabled ? _accent.withValues(alpha: 0.08) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: enabled ? _accent.withValues(alpha: 0.35) : Colors.grey.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isNext) ...[
                Icon(icon, size: r.size(12),
                    color: enabled ? _accent : Colors.grey.shade400),
                SizedBox(width: r.spacing(5)),
              ],
              Text(label, style: GoogleFonts.comicNeue(
                fontSize: r.font(12), fontWeight: FontWeight.w900,
                color: enabled ? _textPrimary : Colors.grey.shade400,
              )),
              if (isNext) ...[
                SizedBox(width: r.spacing(5)),
                Icon(icon, size: r.size(12),
                    color: enabled ? _accent : Colors.grey.shade400),
              ],
            ],
          ),
        ),
      );
}

class _StatChip extends StatelessWidget {
  final String emoji;
  final int count;
  final String label;
  final Color color;
  final ResponsiveHelper r;
  const _StatChip({required this.emoji, required this.count,
      required this.label, required this.color, required this.r});
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: TextStyle(fontSize: r.font(16))),
          SizedBox(height: r.spacing(2)),
          Text('$count', style: GoogleFonts.comicNeue(
              fontSize: r.font(18), fontWeight: FontWeight.w900, color: color)),
          Text(label, style: GoogleFonts.comicNeue(
              fontSize: r.font(10), color: Colors.grey.shade600,
              fontWeight: FontWeight.bold)),
        ],
      );
}

class _ColorLegend extends StatelessWidget {
  final Color color;
  final String label;
  final ResponsiveHelper r;
  const _ColorLegend({required this.color, required this.label, required this.r});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: r.size(10), height: r.size(10),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: r.spacing(4)),
          Text(label, style: GoogleFonts.comicNeue(
              fontSize: r.font(10), color: Colors.grey.shade700,
              fontWeight: FontWeight.bold)),
        ],
      );
}

// ── Chip kata bermasalah di Feedback Panel ──────────────────────────────────────────
class _FeedbackWordChip extends StatelessWidget {
  final _FeedbackWord feedbackWord;
  final bool isActive;
  final ResponsiveHelper r;
  final Color evalWrong;
  final Color evalPartial;

  const _FeedbackWordChip({
    required this.feedbackWord,
    required this.isActive,
    required this.r,
    required this.evalWrong,
    required this.evalPartial,
  });

  Color get _chipColor {
    switch (feedbackWord.status) {
      case WordStatus.incorrect:         return evalWrong;
      case WordStatus.partially_correct: return evalPartial;
      case WordStatus.missed:            return Colors.blueGrey.shade400;
      default:                           return Colors.grey;
    }
  }

  String get _chipEmoji {
    switch (feedbackWord.status) {
      case WordStatus.incorrect:         return '❌';
      case WordStatus.partially_correct: return '🟡';
      case WordStatus.missed:            return '⚪';
      default:                           return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _chipColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.symmetric(
          horizontal: r.spacing(12), vertical: r.spacing(7)),
      decoration: BoxDecoration(
        color: isActive
            ? color.withValues(alpha: 0.18)
            : color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isActive ? color : color.withValues(alpha: 0.4),
          width: isActive ? 2.0 : 1.2,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.30),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_chipEmoji, style: TextStyle(fontSize: r.font(12))),
          SizedBox(width: r.spacing(4)),
          Text(
            feedbackWord.word,
            style: GoogleFonts.comicNeue(
              fontSize: r.font(14),
              fontWeight: isActive ? FontWeight.w900 : FontWeight.bold,
              color: isActive ? color : color.withValues(alpha: 0.85),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mini legenda di bawah chip panel ──────────────────────────────────────────────
class _MiniLegend extends StatelessWidget {
  final Color color;
  final String emoji;
  final String label;
  final ResponsiveHelper r;
  const _MiniLegend({
    required this.color, required this.emoji,
    required this.label, required this.r,
  });
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: TextStyle(fontSize: r.font(10))),
          SizedBox(width: r.spacing(3)),
          Text(
            label,
            style: GoogleFonts.comicNeue(
              fontSize: r.font(9),
              color: color.withValues(alpha: 0.8),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
}