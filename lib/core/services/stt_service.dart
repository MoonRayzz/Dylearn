// stt_service.dart

// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

class SttService {
  static final SttService _instance = SttService._internal();
  factory SttService() => _instance;
  SttService._internal();

  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isInitialized = false;

  // ── ValueNotifier TIDAK PERNAH di-dispose pada singleton ──────────────────
  // Singleton hidup selama app berjalan. Memanggil .dispose() pada ValueNotifier
  // di singleton menyebabkan FlutterError di sesi berikutnya karena instance
  // yang sama masih dipakai. Gunakan resetSession() untuk membersihkan state
  // antar sesi tanpa merusak notifier.
  final ValueNotifier<bool>   isListeningNotifier    = ValueNotifier<bool>(false);
  final ValueNotifier<String> recognizedTextNotifier = ValueNotifier<String>('');
  final ValueNotifier<String> errorNotifier          = ValueNotifier<String>('');

  // ── Adaptive pauseFor ─────────────────────────────────────────────────────
  static const int    _historySize    = 5;
  static const double _defaultPauseMs = 7000.0;

  final List<double> _wpmHistory = [];
  DateTime? _sessionStart;

  // ── Timer & state ─────────────────────────────────────────────────────────
  Timer? _doneTimer;
  bool   _hasFinalResult = false;

  // ════════════════════════════════════════════════════════════════════════════
  // Public API
  // ════════════════════════════════════════════════════════════════════════════

  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speechToText.initialize(
        onStatus: _onStatus,
        onError:  _onError,
        debugLogging: false,
      );
      return _isInitialized;
    } catch (e) {
      debugPrint('Gagal inisialisasi STT: $e');
      errorNotifier.value = 'Mikrofon tidak dapat diakses.';
      return false;
    }
  }

  Future<void> startListening() async {
    if (!_isInitialized) {
      final bool ready = await initialize();
      if (!ready) return;
    }
    if (isListeningNotifier.value) return;

    _hasFinalResult = false;
    _sessionStart   = DateTime.now();
    _doneTimer?.cancel();

    recognizedTextNotifier.value = '';
    errorNotifier.value          = '';

    final int pauseMs = _computePauseFor().round();
    debugPrint('STT pauseFor: ${pauseMs}ms | WPM history: $_wpmHistory');

    try {
      await _speechToText.listen(
        onResult:       _onSpeechResult,
        localeId:       'id_ID',
        cancelOnError:  true,
        partialResults: true,
        listenMode:     stt.ListenMode.dictation,
        listenFor:      const Duration(seconds: 120),
        pauseFor:       Duration(milliseconds: pauseMs),
      );
      isListeningNotifier.value = true;
    } catch (e) {
      debugPrint('Error saat mulai mendengarkan: $e');
      errorNotifier.value       = 'Gagal memulai perekaman suara.';
      isListeningNotifier.value = false;
    }
  }

  Future<void> stopListening() async {
    if (!isListeningNotifier.value) return;
    _hasFinalResult = false;
    await _speechToText.stop();
    _doneTimer?.cancel();
    _doneTimer = Timer(const Duration(milliseconds: 700), () {
      if (isListeningNotifier.value) {
        isListeningNotifier.value = false;
      }
    });
  }

  Future<void> cancelListening() async {
    _doneTimer?.cancel();
    await _speechToText.cancel();
    isListeningNotifier.value    = false;
    recognizedTextNotifier.value = '';
  }

  /// Bersihkan state antar sesi tanpa merusak ValueNotifier.
  /// Dipanggil oleh widget saat di-unmount, bukan dispose().
  void resetSession() {
    _doneTimer?.cancel();
    _hasFinalResult = false;
    _sessionStart   = null;
    if (isListeningNotifier.value) {
      _speechToText.cancel();
      isListeningNotifier.value = false;
    }
    recognizedTextNotifier.value = '';
    errorNotifier.value          = '';
    // _isInitialized TIDAK di-reset: koneksi mikrofon tetap valid
    // _wpmHistory TIDAK di-reset: data adaptif tetap berguna lintas sesi
  }

  /// Hanya dipanggil saat app benar-benar ditutup (AppLifecycleState.detached).
  /// JANGAN panggil dari widget dispose() — singleton akan rusak.
  void disposeForAppExit() {
    _doneTimer?.cancel();
    _speechToText.cancel();
    _isInitialized = false;
    // ValueNotifier TIDAK di-dispose di sini karena singleton mungkin
    // masih diakses oleh widget lain yang sedang teardown bersamaan.
    // OS akan membersihkan memori saat app benar-benar ditutup.
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Adaptive pauseFor
  // ════════════════════════════════════════════════════════════════════════════

  double _computePauseFor() {
    if (_wpmHistory.isEmpty) return _defaultPauseMs;
    final double avgWpm =
        _wpmHistory.reduce((a, b) => a + b) / _wpmHistory.length;
    if (avgWpm < 10) return 9000;
    if (avgWpm < 20) return 7000;
    if (avgWpm < 40) return 6000;
    if (avgWpm < 80) return 4500;
    return 3500;
  }

  void _recordSessionWpm(String finalText) {
    if (_sessionStart == null) return;
    final double durationSec =
        DateTime.now().difference(_sessionStart!).inMilliseconds / 1000.0;
    if (durationSec < 1.0) return;
    final int wordCount = finalText.trim().isEmpty
        ? 0
        : finalText.trim().split(RegExp(r'\s+')).length;
    if (wordCount < 2) return;
    final double wpm = (wordCount / durationSec) * 60.0;
    _wpmHistory.add(wpm);
    if (_wpmHistory.length > _historySize) _wpmHistory.removeAt(0);
    debugPrint('STT WPM: ${wpm.toStringAsFixed(1)} | history: $_wpmHistory');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Callbacks
  // ════════════════════════════════════════════════════════════════════════════

  void _onSpeechResult(SpeechRecognitionResult result) {
    recognizedTextNotifier.value = result.recognizedWords;
    if (result.finalResult) {
      _hasFinalResult = true;
      _doneTimer?.cancel();
      _recordSessionWpm(result.recognizedWords);
      Future.microtask(() => isListeningNotifier.value = false);
    }
  }

  void _onStatus(String status) {
    if (status == 'listening') {
      isListeningNotifier.value = true;
      return;
    }
    if (status == 'done' || status == 'notListening') {
      if (_hasFinalResult) return;
      _doneTimer?.cancel();
      _doneTimer = Timer(const Duration(milliseconds: 400), () {
        isListeningNotifier.value = false;
      });
    }
  }

  void _onError(SpeechRecognitionError error) {
    isListeningNotifier.value = false;
    if (error.errorMsg == 'error_speech_timeout' ||
        error.errorMsg == 'error_no_match') {
      errorNotifier.value = 'Tidak ada suara yang terdengar. Ayo coba lagi!';
    } else if (error.errorMsg != 'error_recognizer_busy') {
      errorNotifier.value = 'Terjadi gangguan teknis. Coba lagi ya.';
    }
  }
}