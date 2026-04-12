// ignore_for_file: deprecated_member_use

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
// PracticeMicPanel — Mode Latihan Membaca Nyaring (Fullscreen)
//
// Fitur utama:
//   • Feedback warna per kata: hijau (benar) / kuning (kurang tepat) / merah (salah)
//   • Underline kata aktif saat TTS berjalan — baik di teks polos maupun hasil evaluasi
//   • Mode Baca Lambat: pauseFor 5 detik + auto-restart agar anak yang baca pelan
//     tidak kehilangan kata karena engine timeout
//   • Mode Eja: suku kata berwarna bergantian, underline tetap muncul di kata aktif
// ══════════════════════════════════════════════════════════════════════════════

class PracticeMicPanel extends StatefulWidget {
  /// Callback saat anak selesai merekam 1 kalimat
  final Function(String recognizedText) onPracticeDone;

  /// Callback saat panel ditutup (kembali ke tab Dengarkan)
  final VoidCallback onCancel;

  /// Callback saat anak menekan "Selesai Latihan & Lihat Rekap"
  final VoidCallback onFinishAll;

  /// Callback pindah ke kalimat berikutnya
  final VoidCallback onNext;

  /// Callback pindah ke kalimat sebelumnya
  final VoidCallback onPrev;

  /// Teks kalimat aktif (panduan + feedback warna di sini)
  final String activeSentenceText;

  /// Index kalimat aktif (0-based)
  final int currentSentenceIndex;

  /// Total kalimat di buku
  final int totalSentences;

  /// Hasil evaluasi kalimat aktif — ditampilkan di kotak kalimat di panel ini
  final List<WordEvaluation>? lastEvaluationResult;

  /// Apakah tombol Sebelumnya aktif
  final bool canGoPrev;

  /// Apakah tombol Berikutnya aktif
  final bool canGoNext;

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

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  bool _showResult = false;
  double _lastAccuracy = 0.0;


  // ── Tema warna ────────────────────────────────────────────────────────────
  static const Color _bgTop = Color(0xFF0D1B4B);
  static const Color _bgBottom = Color(0xFF1A237E);
  static const Color _accent = Color(0xFFFFD54F);
  static const Color _micActive = Color(0xFFEF5350);
  static const Color _micIdle = Color(0xFFFFD54F);
  static const Color _successColor = Color(0xFF66BB6A);
  static const Color _warningColor = Color(0xFFFFA726);

  // ── Warna evaluasi per kata ────────────────────────────────────────────────
  static const Color _evalCorrect = Color(0xFF66BB6A);
  static const Color _evalPartial = Color(0xFFFFA726);
  static const Color _evalWrong   = Color(0xFFEF5350);

  // ── Warna suku kata untuk background gelap panel latihan ──────────────────
  // Lebih terang dari versi reading_components (background krem) agar
  // tetap terbaca di atas gradien navy gelap.
  static const Color _sylColorA = Color(0xFFCE93D8); // ungu muda
  static const Color _sylColorB = Color(0xFF80DEEA); // cyan muda

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
      }
    });
    _flutterTts.setErrorHandler((_) {
      if (mounted) {
        _isTtsPlayingNotifier.value = false;
        _ttsHighlightNotifier.value = null;
      }
    });
    _flutterTts.setProgressHandler((text, start, end, word) {
      if (mounted) _ttsHighlightNotifier.value = TextRange(start: start, end: end);
    });
    _syncResult();
  }

  @override
  void didUpdateWidget(PracticeMicPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentSentenceIndex != oldWidget.currentSentenceIndex) {
      _flutterTts.stop();
      _isTtsPlayingNotifier.value = false;
      _ttsHighlightNotifier.value = null;
      _sttService.recognizedTextNotifier.value = '';
      _sttService.errorNotifier.value = '';
      _syncResult();
    } else if (widget.lastEvaluationResult != oldWidget.lastEvaluationResult) {
      _syncResult();
    }
  }

  void _syncResult() {
    final evals = widget.lastEvaluationResult;
    if (evals != null && evals.isNotEmpty) {
      _lastAccuracy = ReadingEvaluator.calculateOverallAccuracy(evals);
      if (mounted) setState(() => _showResult = true);
    } else {
      if (mounted) setState(() => _showResult = false);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _flutterTts.stop();
    _isTtsPlayingNotifier.dispose();
    _ttsHighlightNotifier.dispose();
    _sttService.isListeningNotifier.removeListener(_onListeningChanged);
    if (_sttService.isListeningNotifier.value) {
      _sttService.cancelListening();
    }
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
      // FIX: jangan langsung ambil recognizedTextNotifier.value di sini.
      //
      // Race condition lama:
      //   isListening → false  (dipanggil dari _onStatus 'done')
      //   _onListeningChanged fire → ambil teks → kata terakhir BELUM ada
      //   _onSpeechResult final result tiba → terlambat, sudah diproses
      //
      // Fix: tunggu 1 microtask agar semua ValueNotifier listener dari
      // _onSpeechResult selesai diproses lebih dulu, BARU ambil teks.
      // Dengan perbaikan di SttService (_onSpeechResult final → set isListening=false
      // via Future.microtask), urutan sekarang adalah:
      //   _onSpeechResult final → recognizedTextNotifier.value = teks lengkap
      //                         → Future.microtask: isListening = false
      //                         → _onListeningChanged fire (teks sudah lengkap)
      // Tapi untuk jaga-jaga (edge case Android lama), tetap pakai microtask di sini
      Future.microtask(() {
        if (!mounted) return;
        final text = _sttService.recognizedTextNotifier.value.trim();
        if (text.isNotEmpty) widget.onPracticeDone(text);
      });
    }
  }

  void _toggleListening() {
    if (_sttService.isListeningNotifier.value) {
      _sttService.stopListening();
    } else {
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

  // ── Helpers skor ──────────────────────────────────────────────────────────
  Color _scoreColor(double s) =>
      s >= 80 ? _successColor : (s >= 50 ? _warningColor : Colors.redAccent);
  String _scoreEmoji(double s) =>
      s >= 90 ? '🌟' : (s >= 75 ? '👍' : (s >= 50 ? '💪' : '🔄'));
  String _scoreMsg(double s) {
    if (s >= 90) return 'Luar Biasa! Sempurna!';
    if (s >= 80) return 'Hebat! Terus berlatih!';
    if (s >= 60) return 'Bagus! Hampir sempurna!';
    if (s >= 40) return 'Ayo coba lagi, kamu bisa!';
    return 'Yuk dicoba sekali lagi!';
  }

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD — FULLSCREEN
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final r = ResponsiveHelper(context);
    // Ambil settings untuk font yang sama dengan halaman Mendengarkan
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
              // ── AppBar mode latihan ───────────────────────────────────────
              _buildTopBar(r),

              // ── Konten utama (scrollable) ─────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: r.spacing(20),
                    vertical: r.spacing(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Kotak kalimat (dengan feedback warna jika sudah dilatih)
                      _buildSentenceCard(r, settings),

                      SizedBox(height: r.spacing(24)),

                      // ── Area mic + status ─────────────────────────────────
                      ValueListenableBuilder<bool>(
                        valueListenable: _sttService.isListeningNotifier,
                        builder: (context, isListening, _) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildMicButton(isListening, r),
                            SizedBox(height: r.spacing(14)),
                            _buildStatusText(isListening, r),


                            // Kartu hasil (skor % + ✅🟡❌)
                            if (_showResult && !isListening) ...[
                              SizedBox(height: r.spacing(12)),
                              _buildResultCard(r),
                            ],
                          ],
                        ),
                      ),

                      // ── Error message ─────────────────────────────────────
                      ValueListenableBuilder<String>(
                        valueListenable: _sttService.errorNotifier,
                        builder: (context, err, _) {
                          if (err.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: EdgeInsets.only(top: r.spacing(10)),
                            child: Text(
                              '⚠️ $err',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.comicNeue(
                                fontSize: r.font(12),
                                color: Colors.redAccent.shade100,
                                fontWeight: FontWeight.bold,
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

              // ── Footer: navigasi + tombol selesai ────────────────────────
              _buildFooter(r),
            ],
          ),
        ),
      ),
    );
  }

  // ── AppBar: badge + counter + tombol kembali ──────────────────────────────
  Widget _buildTopBar(ResponsiveHelper r) => Padding(
        padding: EdgeInsets.fromLTRB(
          r.spacing(16), r.spacing(8), r.spacing(16), 0),
        child: Row(
          children: [
            // Badge MODE LATIHAN
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
                  Icon(Icons.school_rounded,
                      color: _bgBottom, size: r.size(14)),
                  SizedBox(width: r.spacing(5)),
                  Text(
                    'MODE LATIHAN',
                    style: GoogleFonts.comicNeue(
                      fontSize: r.font(11),
                      fontWeight: FontWeight.w900,
                      color: _bgBottom,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(width: r.spacing(10)),

            // Counter kalimat
            if (widget.totalSentences > 0)
              Expanded(
                child: Text(
                  'Kalimat ${widget.currentSentenceIndex + 1} / ${widget.totalSentences}',
                  style: GoogleFonts.comicNeue(
                    fontSize: r.font(12),
                    color: Colors.white60,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              const Expanded(child: SizedBox()),

            // Tombol kembali ke Dengarkan
            GestureDetector(
              onTap: widget.onCancel,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: r.spacing(12), vertical: r.spacing(8)),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.volume_up_rounded,
                        color: Colors.white70, size: r.size(14)),
                    SizedBox(width: r.spacing(5)),
                    Text(
                      'Dengarkan',
                      style: GoogleFonts.comicNeue(
                        fontSize: r.font(11),
                        fontWeight: FontWeight.w900,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  // ── Kotak kalimat: normal atau berwarna (feedback evaluasi) ───────────────
  Widget _buildSentenceCard(ResponsiveHelper r, SettingsProvider settings) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: r.size(120)),
      padding: EdgeInsets.all(r.spacing(20)),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          // Border kuning saat belum/sedang rekam, berubah sesuai skor setelah selesai
          color: _showResult
              ? _scoreColor(_lastAccuracy).withOpacity(0.6)
              : _accent.withOpacity(0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Text(
            _showResult ? 'Hasil bacaanmu:' : 'Bacalah kalimat ini:',
            style: GoogleFonts.comicNeue(
              fontSize: r.font(11),
              color: Colors.white38,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: r.spacing(10)),

          // Selalu listen ke _ttsHighlightNotifier agar underline muncul
          // baik saat teks polos (belum latihan) maupun teks berwarna (sudah latihan).
          ValueListenableBuilder<TextRange?>(
            valueListenable: _ttsHighlightNotifier,
            builder: (context, highlight, _) {
              if (_showResult && widget.lastEvaluationResult != null) {
                return _buildEvaluatedText(
                  widget.activeSentenceText,
                  widget.lastEvaluationResult!,
                  highlight,
                  settings,
                  r,
                );
              }
              return _buildTtsHighlightedText(
                widget.activeSentenceText,
                highlight,
                settings,
                r,
              );
            },
          ),

          // ── Tombol Dengarkan Teks ────────────────────────────────────────
          SizedBox(height: r.spacing(14)),
          ValueListenableBuilder<bool>(
            valueListenable: _isTtsPlayingNotifier,
            builder: (context, isPlaying, _) => GestureDetector(
              onTap: () => _speakSentence(settings),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(
                  horizontal: r.spacing(16),
                  vertical: r.spacing(9),
                ),
                decoration: BoxDecoration(
                  color: isPlaying
                      ? const Color(0xFF29B6F6).withOpacity(0.25)
                      : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isPlaying
                        ? const Color(0xFF29B6F6).withOpacity(0.7)
                        : Colors.white24,
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
                      color: isPlaying
                          ? const Color(0xFF29B6F6)
                          : Colors.white60,
                      size: r.size(16),
                    ),
                    SizedBox(width: r.spacing(7)),
                    Text(
                      isPlaying ? 'Stop' : 'Dengarkan Teks',
                      style: GoogleFonts.comicNeue(
                        fontSize: r.font(12),
                        fontWeight: FontWeight.w900,
                        color: isPlaying
                            ? const Color(0xFF29B6F6)
                            : Colors.white60,
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

  /// Teks panduan (belum dilatih) dengan underline putih pada kata aktif TTS.
  /// Mode eja: suku kata bergantian ungu/cyan, kata aktif dapat underline.
  Widget _buildTtsHighlightedText(
    String text,
    TextRange? highlight,
    SettingsProvider settings,
    ResponsiveHelper r,
  ) {
    final TextStyle base = TextStyle(
      fontFamily: settings.fontFamily,
      fontSize: r.font(20) * settings.textScaleFactor,
      letterSpacing: settings.letterSpacing,
      height: settings.lineHeight,
      color: _accent,
      fontWeight: FontWeight.bold,
    );

    if (!settings.enableSyllable && highlight == null) {
      return Text(text, style: base);
    }

    final segments  = TextUtils.tokenizeWords(text);
    final spans     = <InlineSpan>[];
    int charOffset  = 0;

    for (final seg in segments) {
      final segStart    = charOffset;
      final segEnd      = charOffset + seg.raw.length;
      final isTtsActive = highlight != null &&
          seg.isWord &&
          highlight.start < segEnd &&
          highlight.end   > segStart;

      if (!seg.isWord) {
        spans.add(TextSpan(text: seg.raw, style: base));
        charOffset = segEnd;
        continue;
      }

      final wordSpans = _buildWordSpans(seg, base, _accent, settings);

      if (isTtsActive) {
        spans.add(_underlineSpan(wordSpans, Colors.white, base));
      } else {
        spans.addAll(wordSpans);
      }

      charOffset = segEnd;
    }

    return RichText(text: TextSpan(style: base, children: spans));
  }

  /// Teks berwarna per kata (hasil evaluasi) + underline pada kata aktif TTS.
  /// Mendukung mode eja: semua suku kata dalam satu kata = warna evaluasi sama.
  Widget _buildEvaluatedText(
    String text,
    List<WordEvaluation> evals,
    TextRange? highlight,
    SettingsProvider settings,
    ResponsiveHelper r,
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
    int evalIndex   = 0;
    int charOffset  = 0;

    for (final seg in segments) {
      final segStart = charOffset;
      final segEnd   = charOffset + seg.raw.length;

      if (!seg.isWord) {
        spans.add(TextSpan(
          text: seg.raw,
          style: base.copyWith(color: Colors.white70),
        ));
        charOffset = segEnd;
        continue;
      }

      // Tentukan warna evaluasi untuk kata ini
      Color wordColor = Colors.white;
      if (evalIndex < evals.length) {
        wordColor = _evalColorFor(evals[evalIndex].status);
        evalIndex++;
      }

      // Cek apakah kata ini sedang diucapkan TTS
      final isTtsActive = highlight != null &&
          highlight.start < segEnd &&
          highlight.end   > segStart;

      // Bangun konten kata (plain atau suku kata)
      final wordSpans = _buildWordSpans(seg, base, wordColor, settings);

      if (isTtsActive) {
        // Tambah underline berwarna (warna evaluasi, bukan putih)
        spans.add(_underlineSpan(wordSpans, wordColor, base));
      } else {
        spans.addAll(wordSpans);
      }

      charOffset = segEnd;
    }

    return RichText(
      text: TextSpan(
        style: base.copyWith(color: Colors.white),
        children: spans,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Helper: text rendering
  // ══════════════════════════════════════════════════════════════════════════

  /// Warna evaluasi berdasarkan WordStatus.
  Color _evalColorFor(WordStatus status) {
    switch (status) {
      case WordStatus.correct:           return _evalCorrect;
      case WordStatus.partially_correct: return _evalPartial;
      case WordStatus.incorrect:
      case WordStatus.missed:            return _evalWrong;
    }
  }

  /// Bangun list InlineSpan untuk satu kata.
  /// Mode eja: tiap suku kata bergantian warna A/B dengan warna overide [color].
  /// Mode normal: satu TextSpan dengan [color].
  List<InlineSpan> _buildWordSpans(
    dynamic seg,          // WordSegment dari TextUtils.tokenizeWords
    TextStyle base,
    Color color,
    SettingsProvider settings,
  ) {
    if (settings.enableSyllable && seg.syllables.isNotEmpty) {
      return seg.syllables
          .map<InlineSpan>((syl) => TextSpan(
                text: syl.text,
                // Mode eja: pakai warna evaluasi/accent, bukan warna suku kata bawaan
                // saat ada evaluasi/TTS agar kontras tetap terjaga
                style: base.copyWith(color: color),
              ))
          .toList();
    }
    return [TextSpan(text: seg.raw, style: base.copyWith(color: color))];
  }

  /// Bungkus [wordSpans] dengan Container underline [underlineColor].
  /// padding.bottom = jarak antara baseline teks dan garis bawah.
  WidgetSpan _underlineSpan(
    List<InlineSpan> wordSpans,
    Color underlineColor,
    TextStyle base,
  ) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Container(
        padding: const EdgeInsets.only(bottom: 5),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: underlineColor, width: 2.5),
          ),
        ),
        child: RichText(
          text: TextSpan(style: base, children: wordSpans),
        ),
      ),
    );
  }


  // ── Tombol mic dengan animasi pulse ───────────────────────────────────────
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
                  width: r.size(80),
                  height: r.size(80),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _micActive.withOpacity(0.15),
                  ),
                ),
              ),
              Transform.scale(
                scale: _pulseAnimation.value * 1.25,
                child: Container(
                  width: r.size(80),
                  height: r.size(80),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _micActive.withOpacity(0.25),
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
                        ? [_micActive, _micActive.withOpacity(0.75)]
                        : [_micIdle, _micIdle.withOpacity(0.75)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isListening ? _micActive : _micIdle)
                          .withOpacity(0.5),
                      blurRadius: isListening ? 28 : 14,
                      spreadRadius: isListening ? 4 : 0,
                    ),
                  ],
                ),
                child: Icon(
                  isListening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: isListening ? Colors.white : _bgBottom,
                  size: r.size(44),
                ),
              ),
            ),
          ],
        ),
      );

  // ── Status teks (mendengarkan / idle) ─────────────────────────────────────
  Widget _buildStatusText(bool isListening, ResponsiveHelper r) {
    if (_showResult) return const SizedBox.shrink();
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
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        : Text(
            'Tekan tombol & baca dengan lantang! 😊',
            textAlign: TextAlign.center,
            style: GoogleFonts.comicNeue(
              fontSize: r.font(13),
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          );
  }

  // ── Kartu hasil evaluasi (skor % + ringkasan kata) ────────────────────────
  Widget _buildResultCard(ResponsiveHelper r) {
    final color = _scoreColor(_lastAccuracy);

    int correct = 0, partial = 0, wrong = 0;
    for (final e in widget.lastEvaluationResult ?? []) {
      switch (e.status) {
        case WordStatus.correct:
          correct++;
          break;
        case WordStatus.partially_correct:
          partial++;
          break;
        case WordStatus.incorrect:
        case WordStatus.missed:
          wrong++;
          break;
      }
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(r.spacing(16)),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Skor besar
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_scoreEmoji(_lastAccuracy),
                  style: TextStyle(fontSize: r.font(26))),
              SizedBox(width: r.spacing(8)),
              Text(
                '${_lastAccuracy.toStringAsFixed(0)}%',
                style: GoogleFonts.comicNeue(
                  fontSize: r.font(34),
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1,
                ),
              ),
            ],
          ),
          SizedBox(height: r.spacing(4)),
          Text(
            _scoreMsg(_lastAccuracy),
            style: GoogleFonts.comicNeue(
              fontSize: r.font(12),
              color: Colors.white60,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: r.spacing(12)),

          // Legenda warna
          Wrap(
            alignment: WrapAlignment.center,
            spacing: r.spacing(12),
            runSpacing: r.spacing(6),
            children: [
              _ColorLegend(
                  color: _evalCorrect, label: '✅ Benar', r: r),
              _ColorLegend(
                  color: _evalPartial, label: '🟡 Kurang Tepat', r: r),
              _ColorLegend(
                  color: _evalWrong, label: '❌ Salah/Lewat', r: r),
            ],
          ),
          SizedBox(height: r.spacing(10)),

          // Ringkasan angka
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatChip(
                  emoji: '✅', count: correct, label: 'Benar',
                  color: _successColor, r: r),
              Container(
                  width: 1, height: 36,
                  color: Colors.white.withOpacity(0.15)),
              _StatChip(
                  emoji: '🟡', count: partial, label: 'Kurang',
                  color: _warningColor, r: r),
              Container(
                  width: 1, height: 36,
                  color: Colors.white.withOpacity(0.15)),
              _StatChip(
                  emoji: '❌', count: wrong, label: 'Salah',
                  color: Colors.redAccent, r: r),
            ],
          ),
          SizedBox(height: r.spacing(12)),

          // Tombol Coba Lagi
          GestureDetector(
            onTap: () {
              setState(() => _showResult = false);
              _sttService.recognizedTextNotifier.value = '';
              _sttService.errorNotifier.value = '';
            },
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: r.spacing(20), vertical: r.spacing(8)),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded,
                      color: Colors.white70, size: r.size(14)),
                  SizedBox(width: r.spacing(5)),
                  Text(
                    'Coba Lagi',
                    style: GoogleFonts.comicNeue(
                      fontSize: r.font(12),
                      fontWeight: FontWeight.w900,
                      color: Colors.white70,
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

  // ── Footer: navigasi Prev/Next + tombol Selesai ───────────────────────────
  Widget _buildFooter(ResponsiveHelper r) => Container(
        padding: EdgeInsets.fromLTRB(
          r.spacing(16), r.spacing(12), r.spacing(16), r.spacing(16)),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.25),
          border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.1))),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Navigasi: Prev | progress dots | Next
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _NavButton(
                    icon: Icons.arrow_back_ios_rounded,
                    label: 'Sebelumnya',
                    enabled: widget.canGoPrev,
                    onTap: widget.onPrev,
                    r: r,
                  ),

                  // Progress dots jika ≤ 10 kalimat
                  if (widget.totalSentences > 1 &&
                      widget.totalSentences <= 10)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        widget.totalSentences,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin:
                              EdgeInsets.symmetric(horizontal: r.spacing(2)),
                          width: i == widget.currentSentenceIndex
                              ? r.size(14)
                              : r.size(5),
                          height: r.size(5),
                          decoration: BoxDecoration(
                            color: i == widget.currentSentenceIndex
                                ? _accent
                                : Colors.white.withOpacity(0.3),
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
                        color: Colors.white60,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                  _NavButton(
                    icon: Icons.arrow_forward_ios_rounded,
                    label: 'Berikutnya',
                    enabled: widget.canGoNext,
                    onTap: widget.onNext,
                    r: r,
                    isNext: true,
                  ),
                ],
              ),

              SizedBox(height: r.spacing(12)),

              // Tombol Selesai Latihan
              GestureDetector(
                onTap: widget.onFinishAll,
                child: Container(
                  width: double.infinity,
                  padding:
                      EdgeInsets.symmetric(vertical: r.spacing(13)),
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.flag_rounded,
                          color: _bgBottom, size: r.size(18)),
                      SizedBox(width: r.spacing(7)),
                      Text(
                        'Selesai Latihan & Lihat Rekap',
                        style: GoogleFonts.comicNeue(
                          fontSize: r.font(14),
                          fontWeight: FontWeight.w900,
                          color: _bgBottom,
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

// ══════════════════════════════════════════════════════════════════════════════
// Widget pembantu
// ══════════════════════════════════════════════════════════════════════════════

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final ResponsiveHelper r;
  final bool isNext;

  static const Color _accent = Color(0xFFFFD54F);

  const _NavButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    required this.r,
    this.isNext = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
              horizontal: r.spacing(12), vertical: r.spacing(8)),
          decoration: BoxDecoration(
            color: enabled
                ? _accent.withOpacity(0.15)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: enabled
                  ? _accent.withOpacity(0.4)
                  : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isNext) ...[
                Icon(icon,
                    size: r.size(12),
                    color: enabled ? _accent : Colors.white24),
                SizedBox(width: r.spacing(5)),
              ],
              Text(
                label,
                style: GoogleFonts.comicNeue(
                  fontSize: r.font(12),
                  fontWeight: FontWeight.w900,
                  color: enabled ? _accent : Colors.white24,
                ),
              ),
              if (isNext) ...[
                SizedBox(width: r.spacing(5)),
                Icon(icon,
                    size: r.size(12),
                    color: enabled ? _accent : Colors.white24),
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

  const _StatChip({
    required this.emoji,
    required this.count,
    required this.label,
    required this.color,
    required this.r,
  });

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: TextStyle(fontSize: r.font(16))),
          SizedBox(height: r.spacing(2)),
          Text(
            '$count',
            style: GoogleFonts.comicNeue(
              fontSize: r.font(18),
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.comicNeue(
              fontSize: r.font(10),
              color: Colors.white54,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
}

class _ColorLegend extends StatelessWidget {
  final Color color;
  final String label;
  final ResponsiveHelper r;

  const _ColorLegend({
    required this.color,
    required this.label,
    required this.r,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: r.size(10),
            height: r.size(10),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: r.spacing(4)),
          Text(
            label,
            style: GoogleFonts.comicNeue(
              fontSize: r.font(10),
              color: Colors.white60,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
}