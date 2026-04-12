import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TutorialService {
  static final FlutterTts _flutterTts = FlutterTts();
  static bool _isInitialized = false;

  static const String _keyTtsRate  = 'tts_rate';
  static const String _keyTtsPitch = 'tts_pitch';
  static const String _keyTtsVoice = 'tts_voice_json';

  static Future<void> _applySavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final double rate  = prefs.getDouble(_keyTtsRate)  ?? 0.5;
      final double pitch = prefs.getDouble(_keyTtsPitch) ?? 1.0;
      await _flutterTts.setSpeechRate(rate);
      await _flutterTts.setPitch(pitch);

      final String? voiceJson = prefs.getString(_keyTtsVoice);
      if (voiceJson != null) {
        try {
          final Map<String, String> voice =
              Map<String, String>.from(jsonDecode(voiceJson));
          final String? name   = voice['name'];
          final String? locale = voice['locale'];
          // FIX: null-check sebelum akses — force unwrap voice["name"]! crash
          // jika JSON tersimpan tidak lengkap (misal setelah migrasi data)
          if (name != null && name.isNotEmpty &&
              locale != null && locale.isNotEmpty) {
            await _flutterTts.setVoice({'name': name, 'locale': locale});
          }
        } catch (e) {
          debugPrint('Gagal parse voice JSON: $e');
          await _setFallbackDefaultVoice();
        }
      } else {
        await _setFallbackDefaultVoice();
      }
    } catch (e) {
      debugPrint('Gagal menerapkan pengaturan suara Showcase: $e');
    }
  }

  static Future<void> _setFallbackDefaultVoice() async {
    try {
      final voices = await _flutterTts.getVoices;
      if (voices != null) {
        final List<Map<String, String>> validVoices = [];
        for (final voice in voices) {
          try {
            final Map<String, String> v =
                Map<String, String>.from(voice.cast<String, String>());
            final String locale = (v['locale'] ?? '').toLowerCase();
            final String name   = (v['name'] ?? '').toLowerCase();
            if (!locale.startsWith('id')) continue;
            if (name.contains('network') || v['networkRequired'] == 'true') continue;
            validVoices.add(v);
          } catch (_) {}
        }

        if (validVoices.isNotEmpty) {
          int targetIndex = 4;
          if (validVoices.length <= targetIndex) {
            targetIndex = validVoices.length - 1;
          }
          // FIX: null-check sebelum set voice — konsisten dengan _applySavedSettings
          final String? name   = validVoices[targetIndex]['name'];
          final String? locale = validVoices[targetIndex]['locale'];
          if (name != null && name.isNotEmpty &&
              locale != null && locale.isNotEmpty) {
            await _flutterTts.setVoice({'name': name, 'locale': locale});
          }
        }
      }
    } catch (e) {
      debugPrint('Gagal set default fallback voice: $e');
    }
  }

  static Future<void> speakShowcaseText(String text) async {
    if (text.isEmpty) return;

    if (!_isInitialized) {
      await _flutterTts.setLanguage('id-ID');
      await _flutterTts.awaitSpeakCompletion(true);
      _isInitialized = true;
    }

    await _applySavedSettings();
    await _flutterTts.speak(text);
  }

  static Future<void> stopSpeaking() async {
    await _flutterTts.stop();
  }

  static Future<bool> hasSeenTutorial(String tutorialKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('tutorial_seen_$tutorialKey') ?? false;
  }

  static Future<void> markTutorialAsSeen(String tutorialKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tutorial_seen_$tutorialKey', true);
  }
}