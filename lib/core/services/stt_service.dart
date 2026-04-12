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
  bool _isDisposed    = false;

  final ValueNotifier<bool>   isListeningNotifier    = ValueNotifier<bool>(false);
  final ValueNotifier<String> recognizedTextNotifier = ValueNotifier<String>('');
  final ValueNotifier<String> errorNotifier          = ValueNotifier<String>('');

  // ── Adaptive pauseFor ─────────────────────────────────────────────────────
  // Sistem mengukur kecepatan baca anak (WPM) dari sesi-sesi sebelumnya
  // dan menyesuaikan pauseFor secara otomatis sebelum setiap listen().
  //
  // Konversi WPM → pauseFor:
  //   < 20 WPM  (sangat lambat, eja per huruf) → 5000ms
  //   20–40 WPM (lambat)                       → 4000ms
  //   40–80 WPM (normal)                       → 3000ms
  //   > 80 WPM  (cepat/lancar)                 → 2500ms
  //
  // Sesi pertama: 4000ms (asumsi lambat, aman untuk semua anak).
  // Sistem belajar dari sesi berikutnya — rolling average 5 sesi terakhir.

  static const int    _historySize    = 5;
  static const double _defaultPauseMs = 4000.0;

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
      if (!_isDisposed) errorNotifier.value = 'Mikrofon tidak dapat diakses.';
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

    if (!_isDisposed) {
      recognizedTextNotifier.value = '';
      errorNotifier.value          = '';
    }

    final int pauseMs = _computePauseFor().round();
    debugPrint('STT pauseFor: ${pauseMs}ms | WPM history: $_wpmHistory');

    try {
      await _speechToText.listen(
        onResult:       _onSpeechResult,
        localeId:       'id_ID',
        cancelOnError:  true,
        partialResults: true,
        listenMode:     stt.ListenMode.dictation,
        listenFor:      const Duration(seconds: 60),
        pauseFor:       Duration(milliseconds: pauseMs),
      );
      if (!_isDisposed) isListeningNotifier.value = true;
    } catch (e) {
      debugPrint('Error saat mulai mendengarkan: $e');
      if (!_isDisposed) {
        errorNotifier.value       = 'Gagal memulai perekaman suara.';
        isListeningNotifier.value = false;
      }
    }
  }

  Future<void> stopListening() async {
    if (!isListeningNotifier.value) return;
    _hasFinalResult = false;
    await _speechToText.stop();
    _doneTimer?.cancel();
    _doneTimer = Timer(const Duration(milliseconds: 700), () {
      if (!_isDisposed && isListeningNotifier.value) {
        isListeningNotifier.value = false;
      }
    });
  }

  Future<void> cancelListening() async {
    _doneTimer?.cancel();
    await _speechToText.cancel();
    if (!_isDisposed) {
      isListeningNotifier.value    = false;
      recognizedTextNotifier.value = '';
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed    = true;
    _isInitialized = false;
    _doneTimer?.cancel();
    _speechToText.cancel();
    isListeningNotifier.dispose();
    recognizedTextNotifier.dispose();
    errorNotifier.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Adaptive pauseFor
  // ════════════════════════════════════════════════════════════════════════════

  double _computePauseFor() {
    if (_wpmHistory.isEmpty) return _defaultPauseMs;
    final double avgWpm =
        _wpmHistory.reduce((a, b) => a + b) / _wpmHistory.length;
    if (avgWpm < 20) return 5000;
    if (avgWpm < 40) return 4000;
    if (avgWpm < 80) return 3000;
    return 2500;
  }

  void _recordSessionWpm(String finalText) {
    if (_sessionStart == null) return;
    final double durationSec =
        DateTime.now().difference(_sessionStart!).inMilliseconds / 1000.0;
    if (durationSec < 1.0) return;

    final int wordCount = finalText.trim().isEmpty
        ? 0
        : finalText.trim().split(RegExp(r'\s+')).length;
    if (wordCount < 2) return; // terlalu sedikit untuk estimasi akurat

    final double wpm = (wordCount / durationSec) * 60.0;
    _wpmHistory.add(wpm);
    if (_wpmHistory.length > _historySize) _wpmHistory.removeAt(0);
    debugPrint('STT WPM: ${wpm.toStringAsFixed(1)} | history: $_wpmHistory');
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Callbacks
  // ════════════════════════════════════════════════════════════════════════════

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (_isDisposed) return;
    recognizedTextNotifier.value = result.recognizedWords;
    if (result.finalResult) {
      _hasFinalResult = true;
      _doneTimer?.cancel();
      _recordSessionWpm(result.recognizedWords);
      Future.microtask(() {
        if (!_isDisposed) isListeningNotifier.value = false;
      });
    }
  }

  void _onStatus(String status) {
    if (_isDisposed) return;
    if (status == 'listening') {
      isListeningNotifier.value = true;
      return;
    }
    if (status == 'done' || status == 'notListening') {
      if (_hasFinalResult) return;
      _doneTimer?.cancel();
      _doneTimer = Timer(const Duration(milliseconds: 400), () {
        if (!_isDisposed) isListeningNotifier.value = false;
      });
    }
  }

  void _onError(SpeechRecognitionError error) {
    if (_isDisposed) return;
    isListeningNotifier.value = false;
    if (error.errorMsg == 'error_speech_timeout' ||
        error.errorMsg == 'error_no_match') {
      errorNotifier.value = 'Tidak ada suara yang terdengar. Ayo coba lagi!';
    } else if (error.errorMsg != 'error_recognizer_busy') {
      errorNotifier.value = 'Terjadi gangguan teknis. Coba lagi ya.';
    }
  }
}