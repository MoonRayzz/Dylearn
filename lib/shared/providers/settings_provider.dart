// ignore_for_file: curly_braces_in_flow_control_structures, depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SettingsProvider with ChangeNotifier {
  static const String _keyTextScale      = 'app_text_scale';
  static const String _keyTtsRate        = 'tts_rate';
  static const String _keyTtsPitch       = 'tts_pitch';
  static const String _keyTtsVoice       = 'tts_voice_json';
  static const String _keyEnableSyllable = 'enable_syllable';
  static const String _keyEnableRuler    = 'enable_ruler';
  static const String _keyRulerOpacity   = 'ruler_opacity';
  static const String _keyThemeMode      = 'theme_mode';
  static const String _keyLanguageCode   = 'language_code';
  static const String _keyFontFamily     = 'app_font_family';
  static const String _keyLetterSpacing  = 'app_letter_spacing';
  static const String _keyLineHeight       = 'app_line_height';
  static const String _keyFeedbackTts     = 'enable_feedback_tts';

  static const MapEquality<String, String> _mapEquality = MapEquality();

  SharedPreferences? _prefs;
  final Map<String, Timer> _saveTimers = {};

  // FIX: flag disposed untuk guard semua async callback post-dispose
  bool _isDisposed = false;

  double _textScaleFactor = 1.0;
  double _ttsRate         = 0.45;
  double _ttsPitch        = 1.1;
  Map<String, String>? _selectedVoice;

  bool   _enableSyllable  = false;
  bool   _enableRuler     = false;
  bool   _enableFeedbackTts = true;
  double _rulerOpacity    = 0.6;

  String _fontFamily      = 'OpenDyslexic';
  double _letterSpacing   = 1.5;
  double _lineHeight      = 1.8;

  ThemeMode _themeMode    = ThemeMode.light;
  Locale    _locale       = const Locale('id', 'ID');

  double get textScaleFactor  => _textScaleFactor;
  double get ttsRate          => _ttsRate;
  double get ttsPitch         => _ttsPitch;
  Map<String, String>? get selectedVoice => _selectedVoice;
  bool   get enableSyllable      => _enableSyllable;
  bool   get enableRuler         => _enableRuler;
  bool   get enableFeedbackTts   => _enableFeedbackTts;
  double get rulerOpacity        => _rulerOpacity;
  String get fontFamily       => _fontFamily;
  double get letterSpacing    => _letterSpacing;
  double get lineHeight       => _lineHeight;
  ThemeMode get themeMode     => _themeMode;
  Locale get locale           => _locale;
  bool get isLoaded           => _prefs != null;

  SettingsProvider() {
    _initSettings();
  }

  // FIX: dispose() — cancel semua pending timer agar tidak fire setelah destroyed
  // dan tidak force-unwrap _prefs! pada state yang sudah tidak valid
  @override
  void dispose() {
    _isDisposed = true;
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    _saveTimers.clear();
    super.dispose();
  }

  Future<void> _initSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (_isDisposed) return;

    _textScaleFactor = prefs.getDouble(_keyTextScale)     ?? 1.0;
    _ttsRate         = prefs.getDouble(_keyTtsRate)       ?? 0.45;
    _ttsPitch        = prefs.getDouble(_keyTtsPitch)      ?? 1.1;
    _enableSyllable    = prefs.getBool(_keyEnableSyllable)  ?? false;
    _enableRuler       = prefs.getBool(_keyEnableRuler)     ?? false;
    _enableFeedbackTts = prefs.getBool(_keyFeedbackTts)     ?? true;
    _rulerOpacity      = prefs.getDouble(_keyRulerOpacity)  ?? 0.6;
    _fontFamily      = prefs.getString(_keyFontFamily)    ?? 'OpenDyslexic';
    _letterSpacing   = prefs.getDouble(_keyLetterSpacing) ?? 1.5;
    _lineHeight      = prefs.getDouble(_keyLineHeight)    ?? 1.8;

    final String? voiceJson = prefs.getString(_keyTtsVoice);
    if (voiceJson != null) {
      try {
        _selectedVoice = Map<String, String>.from(jsonDecode(voiceJson));
      } catch (e) {
        _selectedVoice = null;
        await prefs.remove(_keyTtsVoice);
      }
    }

    if (_selectedVoice == null) {
      await _autoSetVarian5AsDefault(prefs);
    }

    final String? themeString = prefs.getString(_keyThemeMode);
    if (themeString == 'light')       _themeMode = ThemeMode.light;
    else if (themeString == 'dark')   _themeMode = ThemeMode.dark;
    else if (themeString == 'system') _themeMode = ThemeMode.system;
    else                              _themeMode = ThemeMode.light;

    final String? langCode = prefs.getString(_keyLanguageCode);
    _locale = (langCode == 'en')
        ? const Locale('en', 'US')
        : const Locale('id', 'ID');

    _prefs = prefs;
    if (!_isDisposed) notifyListeners();
  }

  Future<void> _autoSetVarian5AsDefault(SharedPreferences prefs) async {
    final FlutterTts tempTts = FlutterTts();
    try {
      final voices = await tempTts.getVoices;
      if (voices != null) {
        final List<Map<String, String>> validVoices = [];
        for (final voice in voices) {
          try {
            final Map<String, String> v =
                Map<String, String>.from(voice.cast<String, String>());
            final String locale = (v['locale'] ?? '').toLowerCase();
            final String name   = (v['name'] ?? '').toLowerCase();
            if (!locale.startsWith('id')) continue;
            if (name.contains('network') ||
                v['networkRequired'] == 'true') continue;
            validVoices.add(v);
          } catch (castError) {
            debugPrint('Skip voice karena cast error: $castError');
            continue;
          }
        }
        if (validVoices.isNotEmpty) {
          final int targetIndex =
              validVoices.length > 4 ? 4 : validVoices.length - 1;
          _selectedVoice = validVoices[targetIndex];
          await prefs.setString(_keyTtsVoice, jsonEncode(_selectedVoice));
        }
      }
    } catch (e) {
      debugPrint('Gagal auto-set default voice: $e');
    } finally {
      await tempTts.stop();
    }
  }

  bool _canPersist() => _prefs != null && !_isDisposed;

  // FIX: tambah guard _isDisposed di dalam callback timer
  // _canPersist() hanya dicek saat timer dijadwalkan, bukan saat fire —
  // provider bisa sudah dispose() dalam 400ms window tersebut
  void _debounceSave(String key, dynamic value) {
    if (_saveTimers[key]?.isActive ?? false) {
      _saveTimers[key]!.cancel();
    }
    _saveTimers[key] = Timer(const Duration(milliseconds: 400), () {
      _saveTimers.remove(key);
      if (_isDisposed || _prefs == null) return;
      if (value is double)       _prefs!.setDouble(key, value);
      else if (value is bool)    _prefs!.setBool(key, value);
      else if (value is String)  _prefs!.setString(key, value);
    });
  }

  // FIX: guard _isDisposed pada semua Future.microtask agar _prefs! tidak
  // diakses setelah provider sudah di-dispose
  void _microtaskSave(VoidCallback fn) {
    if (!_canPersist()) return;
    Future.microtask(() {
      if (_isDisposed || _prefs == null) return;
      fn();
    });
  }

  void updateTextScale(double value) {
    if (_textScaleFactor == value) return;
    _textScaleFactor = value;
    notifyListeners();
    if (_canPersist()) _debounceSave(_keyTextScale, value);
  }

  void updateLetterSpacing(double value) {
    if (_letterSpacing == value) return;
    _letterSpacing = value;
    notifyListeners();
    if (_canPersist()) _debounceSave(_keyLetterSpacing, value);
  }

  void updateLineHeight(double value) {
    if (_lineHeight == value) return;
    _lineHeight = value;
    notifyListeners();
    if (_canPersist()) _debounceSave(_keyLineHeight, value);
  }

  void updateTtsRate(double value) {
    if (_ttsRate == value) return;
    _ttsRate = value;
    notifyListeners();
    if (_canPersist()) _debounceSave(_keyTtsRate, value);
  }

  void updateTtsPitch(double value) {
    if (_ttsPitch == value) return;
    _ttsPitch = value;
    notifyListeners();
    if (_canPersist()) _debounceSave(_keyTtsPitch, value);
  }

  void updateTtsVoice(Map<String, String> voice) {
    if (_mapEquality.equals(_selectedVoice, voice)) return;
    _selectedVoice = voice;
    notifyListeners();
    _microtaskSave(() => _prefs!.setString(_keyTtsVoice, jsonEncode(voice)));
  }

  void updateFontFamily(String font) {
    if (_fontFamily == font) return;
    _fontFamily = font;
    notifyListeners();
    _microtaskSave(() => _prefs!.setString(_keyFontFamily, font));
  }

  void toggleSyllable(bool value) {
    if (_enableSyllable == value) return;
    _enableSyllable = value;
    notifyListeners();
    _microtaskSave(() => _prefs!.setBool(_keyEnableSyllable, value));
  }

  void toggleRuler(bool value) {
    if (_enableRuler == value) return;
    _enableRuler = value;
    notifyListeners();
    _microtaskSave(() => _prefs!.setBool(_keyEnableRuler, value));
  }

  void toggleFeedbackTts(bool value) {
    if (_enableFeedbackTts == value) return;
    _enableFeedbackTts = value;
    notifyListeners();
    _microtaskSave(() => _prefs!.setBool(_keyFeedbackTts, value));
  }

  void updateRulerOpacity(double value) {
    if (_rulerOpacity == value) return;
    _rulerOpacity = value;
    notifyListeners();
    if (_canPersist()) _debounceSave(_keyRulerOpacity, value);
  }

  void updateThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    String modeStr;
    if (mode == ThemeMode.light)       modeStr = 'light';
    else if (mode == ThemeMode.dark)   modeStr = 'dark';
    else                               modeStr = 'system';

    _microtaskSave(() => _prefs!.setString(_keyThemeMode, modeStr));
  }

  void updateLocale(String langCode) {
    final Locale newLocale = (langCode == 'en')
        ? const Locale('en', 'US')
        : const Locale('id', 'ID');
    if (_locale == newLocale) return;
    _locale = newLocale;
    notifyListeners();
    _microtaskSave(() => _prefs!.setString(_keyLanguageCode, langCode));
  }

  Future<void> resetToDefaults() async {
    // FIX: cancel semua pending timer sebelum reset
    // agar timer lama tidak overwrite nilai yang baru saja di-reset 400ms kemudian
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    _saveTimers.clear();

    _textScaleFactor = 1.0;
    _ttsRate         = 0.45;
    _ttsPitch        = 1.1;
    _selectedVoice   = null;
    _enableSyllable    = false;
    _enableRuler       = false;
    _enableFeedbackTts = true;
    _rulerOpacity      = 0.6;
    _fontFamily        = 'OpenDyslexic';
    _letterSpacing   = 1.5;
    _lineHeight      = 1.8;
    _themeMode       = ThemeMode.light;
    _locale          = const Locale('id', 'ID');

    notifyListeners();

    if (_canPersist()) {
      await Future.wait([
        _prefs!.remove(_keyTextScale),
        _prefs!.remove(_keyTtsRate),
        _prefs!.remove(_keyTtsPitch),
        _prefs!.remove(_keyTtsVoice),
        _prefs!.remove(_keyEnableSyllable),
        _prefs!.remove(_keyEnableRuler),
        _prefs!.remove(_keyFeedbackTts),
        _prefs!.remove(_keyRulerOpacity),
        _prefs!.remove(_keyFontFamily),
        _prefs!.remove(_keyLetterSpacing),
        _prefs!.remove(_keyLineHeight),
        _prefs!.remove(_keyThemeMode),
        _prefs!.remove(_keyLanguageCode),
      ]);
    }
  }
}