// ignore_for_file: depend_on_referenced_packages, unnecessary_import, unused_element, curly_braces_in_flow_control_structures

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../utils/text_utils.dart';
import 'ocr_indonesian_dictionary.dart';
import 'ocr_image_preprocessor.dart';

class _OcrConfig {
  static String? _cachedApiKey;

  static String get geminiApiKey {
    if (_cachedApiKey != null && _cachedApiKey!.isNotEmpty) return _cachedApiKey!;
    try {
      if (dotenv.isInitialized) {
        _cachedApiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
        return _cachedApiKey!;
      }
      return '';
    } catch (e) {
      debugPrint('DotEnv Warning: $e');
      return '';
    }
  }

  static const int    chunkSize               = 3000;
  static const double minimumConfidence       = 0.40;
  static const double wordConfidenceThreshold = 0.70;
  static const int    aiTimeoutSeconds        = 50;

  static const double hallucinationThreshold  = 0.55;
  static const double lengthRatioMin          = 0.80;
  static const double lengthRatioMax          = 1.20;
  static const double wordRatioMin            = 0.80;
  static const double wordRatioMax            = 1.12;
  static const int    maxParagraphDrift       = 2;

  static const double hallucinationThresholdLow = 0.60;
  static const double lengthRatioMinLow         = 0.60;
  static const double lengthRatioMaxLow         = 1.25;
  static const double wordRatioMinLow           = 0.70;
  static const double wordRatioMaxLow           = 1.20;
  static const int    maxParagraphDriftLow      = 4;

  static const int    rateLimitDelayMs        = 4500;
  static const double minimumTextQuality      = 0.50;
}

class OcrResult {
  final ProcessedTextData parsedData;
  final double averageConfidence;
  final Map<String, dynamic> metadata;

  const OcrResult({
    required this.parsedData,
    required this.averageConfidence,
    this.metadata = const {},
  });
}

class ProcessedTextData {
  final String fullRawText;
  final List<String> sentences;
  final List<String> syllabifiedSentences;
  final List<int> sentenceToPageMap;
  final List<int> sentenceToParagraphMap;
  final List<List<int>> pages;

  const ProcessedTextData({
    required this.fullRawText,
    required this.sentences,
    required this.syllabifiedSentences,
    required this.sentenceToPageMap,
    required this.sentenceToParagraphMap,
    required this.pages,
  });

  factory ProcessedTextData.empty() => const ProcessedTextData(
        fullRawText: '',
        sentences: [],
        syllabifiedSentences: [],
        sentenceToPageMap: [],
        sentenceToParagraphMap: [],
        pages: [],
      );
}

class OcrService {
  static TextRecognizer? _textRecognizer;

  // FIX: cache GenerativeModel sebagai static field — lazy init
  // Sebelumnya dibuat ulang setiap _runGeminiTextCorrectionPass dipanggil
  // (bisa 2x per halaman saat double pass) — heavy native object allocation
  static GenerativeModel? _geminiModel;

  static TextRecognizer get _recognizer {
    _textRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _textRecognizer!;
  }

  static GenerativeModel _getGeminiModel() {
    _geminiModel ??= GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _OcrConfig.geminiApiKey,
      generationConfig: GenerationConfig(temperature: 0.0),
    );
    return _geminiModel!;
  }

  static void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
    // FIX: null-kan cached model agar GC bisa reclaim resource
    _geminiModel = null;
    debugPrint('[OcrService] TextRecognizer disposed.');
  }

  static final RegExp _reNoise              = RegExp(r'^[^a-zA-Z\u00C0-\u024F0-9]+$');
  static final RegExp _reListBullet         = RegExp(r'^(\d+[\.\)]|\-|\u2022|\*|[a-zA-Z]\))\s+\S');
  static final RegExp _rePuncEnd            = RegExp(r'[.!?:;]$');
  static final RegExp _reTripleNL           = RegExp(r'\n{3,}');
  static final RegExp _reNextCapital        = RegExp(r'^[A-Z\u201C\u201D]');
  static final RegExp _reCleanWord          = RegExp(r'[^\w\s]');
  static final RegExp _reNoiseSymbols       = RegExp(r'(?<![a-zA-Z])[\*#@~\^\|_]+(?![a-zA-Z])');
  static final RegExp _reMidCapital         = RegExp(r'(?<=[a-z]\s)[A-Z](?=[a-z]+)');
  static final RegExp _reNumericRp          = RegExp(r'(Rp|rp)\s?(\d{1,3}(?:\.\d{3})*)');
  static final RegExp _reNumericUnits       = RegExp(r'\b(\d+)\s?(kg|gr|cm|m|km)\b');
  static final RegExp _rePuncSpaceComma     = RegExp(r'\s+,');
  static final RegExp _rePuncSpaceDot       = RegExp(r'\s+\.');
  static final RegExp _rePuncMultiComma     = RegExp(r',{2,}');
  static final RegExp _rePuncMultiDot       = RegExp(r'\.{4,}');
  static final RegExp _rePuncSpaceFix       = RegExp(r'([.,!?])([A-Za-z])');
  static final RegExp _reAiMdStart          = RegExp(r'^```[a-zA-Z]*\n', multiLine: true);
  static final RegExp _reAiMdEnd            = RegExp(r'\n```$', multiLine: true);
  static final RegExp _reAiPreamble         = RegExp(
    r'^(Berikut|Berikut adalah|Hasil koreksi|Teks yang|Ini adalah)[^\n]*\n',
    caseSensitive: false,
  );
  static final RegExp _reEmptySpaces        = RegExp(r'\s+');
  static final RegExp _reSentenceSplitter   = RegExp(
    r'(?<=[.!?])\s+(?=[A-Z\u201C\u201D\u0022])',
  );
  static final RegExp _reCleanSentenceStart = RegExp(r'^[\W_]+');
  static final RegExp _rePuncEndPrev        = RegExp(r'[.!?]$');
  static final RegExp _reZeroInWord         = RegExp(r'(?<=[a-zA-Z])0(?=[a-zA-Z])');
  static final RegExp _reOneInWord          = RegExp(r'(?<=[a-zA-Z])1(?=[a-zA-Z])');
  static final RegExp _reContinuationPattern = RegExp(
    r'^(dan|atau|tetapi|namun|sehingga|karena|yang|dengan|ke|di|dari|untuk|'
    r'itu|ini|tersebut|pun|juga|lalu|kemudian|setelah|sebelum|ketika|saat|'
    r'hingga|sampai|bahwa|agar|supaya|walaupun|meskipun|padahal|sedangkan|'
    r'melainkan|maupun|serta|sambil)\b',
    caseSensitive: false,
  );
  static final RegExp _reDialogResponsePattern = RegExp(
    r'^(ya|iya|tidak|nggak|enggak|oh|ah|eh|aduh|ayo|sini|sana|oke|'
    r'baik|boleh|mau|bisa|pergi|pulang|sudah|belum|pernah|jangan|'
    r'tolong|maaf|terima|kasih|selamat|halo|hai|hei)\b',
    caseSensitive: false,
  );
  static final RegExp _reStartCapital = RegExp(r'^[A-Z]');

  static const String _fewShotExamples = """
--- CONTOH POLA ERROR OCR BAHASA INDONESIA ---
SALAH : "Arnan pergi ke pasar rnernbeli sayuran clan buah-buahan."
BENAR : "Aman pergi ke pasar membeli sayuran dan buah-buahan."
SALAH : "Sgyq sukg mgkgn gpel yqng mqnis."
BENAR : "Saya suka makan apel yang manis."
SALAH : "Clari mana sqyq bisa mendapatkan air?"
BENAR : "Dari mana saya bisa mendapatkan air?"
--- AKHIR CONTOH ---
""";

  static DateTime? _lastGeminiCallTime;

  static Future<void> _enforceRateLimit() async {
    if (_lastGeminiCallTime != null) {
      final int elapsed =
          DateTime.now().difference(_lastGeminiCallTime!).inMilliseconds;
      if (elapsed < _OcrConfig.rateLimitDelayMs) {
        final int waitMs = _OcrConfig.rateLimitDelayMs - elapsed;
        debugPrint('[RateLimit] Menunggu ${waitMs}ms sebelum request Gemini...');
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }
    _lastGeminiCallTime = DateTime.now();
  }

  static Future<OcrResult> convertImageToText(
    File imageFile, {
    bool cognitiveMode = false,
    Map<String, String> userCustomDictionary = const {},
    ImagePreprocessProfile preprocessProfile = ImagePreprocessProfile.auto,
  }) async {
    PreprocessResult? prepResult;
    File fileForOcr = imageFile;

    try {
      prepResult = await OcrImagePreprocessor.prepare(
        imageFile,
        profile: preprocessProfile,
      );
      fileForOcr = prepResult.processedFile;
    } catch (e) {
      debugPrint('[OcrService] Preprocessor gagal, pakai file asli: $e');
    }

    final InputImage inputImage = InputImage.fromFile(fileForOcr);

    try {
      final RecognizedText recognizedText =
          await _recognizer.processImage(inputImage);
      final Map<String, dynamic> extractionResult =
          _extractAndAnalyzeConfidence(recognizedText);

      String workingText       = extractionResult['rawText'] as String;
      double averageConfidence = extractionResult['confidence'] as double;
      List<String> lowConfWords =
          extractionResult['lowConfidenceWords'] as List<String>;

      if (workingText.trim().isEmpty ||
          averageConfidence < _OcrConfig.minimumConfidence) {
        return OcrResult(
          parsedData: ProcessedTextData.empty(),
          averageConfidence: averageConfidence,
          metadata: {'error': 'Teks tidak ditemukan atau terlalu buram.'},
        );
      }

      workingText = await compute(_runOfflinePipeline, {
        'text': workingText,
        'customDict': userCustomDictionary,
      });

      final double textQuality =
          await compute(_calculateTextQualityIsolate, workingText);
      final bool isLowQualityText = textQuality < _OcrConfig.minimumTextQuality;

      bool isAiEnhanced = false;
      int  passesDone   = 0;

      if (_OcrConfig.geminiApiKey.isNotEmpty) {
        final bool hasInternet = await _checkInternetConnection();
        if (hasInternet) {
          try {
            await _enforceRateLimit();

            final bool requiresDoublePass = averageConfidence < 0.60
                || lowConfWords.length > 15
                || isLowQualityText;

            String aiCorrected = await _runGeminiTextCorrectionPass(
              text:          workingText,
              cognitiveMode: cognitiveMode,
              lowConfWords:  lowConfWords,
              isSecondPass:  false,
            );
            passesDone++;

            if (requiresDoublePass) {
              await _enforceRateLimit();
              aiCorrected = await _runGeminiTextCorrectionPass(
                text:          aiCorrected,
                cognitiveMode: cognitiveMode,
                lowConfWords:  [],
                isSecondPass:  true,
              );
              passesDone++;
            }

            final Map<String, dynamic> validationResult =
                await compute(_validateAiOutputIsolate, {
              'original':      workingText,
              'corrected':     aiCorrected,
              'cognitiveMode': cognitiveMode,
              'isLowQuality':  isLowQualityText,
            });

            if (validationResult['valid'] == true) {
              workingText  = aiCorrected;
              isAiEnhanced = true;
            } else {
              debugPrint(
                  '[OcrValidation] AI Correction Rejected: ${validationResult['reason']}');
            }
          } catch (e) {
            debugPrint('[OcrService] Gemini AI Layer failed: $e');
          }
        }
      }

      final ProcessedTextData finalData =
          await compute(buildTtsReadyOutput, workingText);
      final double finalQuality =
          await compute(_calculateTextQualityIsolate, workingText);

      return OcrResult(
        parsedData:        finalData,
        averageConfidence: averageConfidence,
        metadata: {
          'isAiEnhanced':            isAiEnhanced,
          'aiPasses':                passesDone,
          'totalSentences':          finalData.sentences.length,
          'lowConfidenceWordsCount': lowConfWords.length,
          'textQualityBefore':       textQuality,
          'textQualityAfter':        finalQuality,
          'wasLowQuality':           isLowQualityText,
          'preprocessProfile':       prepResult?.profileUsed.name ?? 'skip',
          'preprocessLuminance':     prepResult?.diagnostics['avgLuminance'],
          'preprocessContrast':      prepResult?.diagnostics['avgContrast'],
          'preprocessFallback':      prepResult?.diagnostics['fallback'] ?? false,
        },
      );
    } catch (e) {
      debugPrint('[OcrService] Critical Error: $e');
      return OcrResult(
          parsedData: ProcessedTextData.empty(), averageConfidence: 0.0);
    } finally {
      if (prepResult != null) {
        await OcrImagePreprocessor.cleanup(prepResult);
      }
    }
  }

  static Map<String, dynamic> _extractAndAnalyzeConfidence(
      RecognizedText recognizedText) {
    final StringBuffer rawBuffer = StringBuffer();
    double totalConf  = 0.0;
    int elementsCount = 0;
    final List<String> lowConfWords = [];

    for (final TextBlock block in recognizedText.blocks) {
      for (final TextLine line in block.lines) {
        rawBuffer.writeln(line.text.trim());
        for (final TextElement element in line.elements) {
          final double conf = element.confidence ?? 0.8;
          totalConf += conf;
          elementsCount++;
          if (conf < _OcrConfig.wordConfidenceThreshold) {
            final String cleanWord = element.text.replaceAll(_reCleanWord, '');
            if (cleanWord.length > 2) lowConfWords.add(cleanWord);
          }
        }
      }
      rawBuffer.writeln();
    }

    return {
      'rawText':            rawBuffer.toString(),
      'confidence':         elementsCount > 0 ? totalConf / elementsCount : 0.0,
      'lowConfidenceWords': lowConfWords,
    };
  }

  static String _applyGenericOcrPatterns(String text) {
    String res = text;
    res = res.replaceAllMapped(
      RegExp(r'([a-zA-Z]+)-\s+([a-zA-Z]+)'),
      (m) => '${m.group(1)}${m.group(2)}',
    );
    res = res.replaceAll(_reZeroInWord, 'o');
    res = res.replaceAll(_reOneInWord, 'l');
    res = res.replaceAll('rnern', 'mem');
    res = res.replaceAll('rnen', 'men');
    res = res.replaceAll(RegExp(r'\bclan\b'), 'dan');
    res = res.replaceAll(RegExp(r'\bclari\b'), 'dari');
    res = res.replaceAll(RegExp(r'\bclengan\b'), 'dengan');
    res = res.replaceAll(RegExp(r'\bsgyq\b'), 'saya');
    res = res.replaceAll(RegExp(r'\bsqyg\b'), 'saya');
    res = res.replaceAll(RegExp(r'\bsqyq\b'), 'saya');
    res = res.replaceAll(RegExp(r'\bsgyg\b'), 'saya');
    res = res.replaceAll(RegExp(r'\byqng\b'), 'yang');
    res = res.replaceAll(RegExp(r'\bygnq\b'), 'yang');
    res = res.replaceAll(RegExp(r'\byqna\b'), 'yang');
    return res;
  }

  static bool _isTitleCandidate(String curr, String next) {
    final String cleanCurr = curr.trim();
    if (cleanCurr.isEmpty) return false;

    final RegExp structural = RegExp(
      r'(?:\b|^)(Bab|Chapter|Prakata|Pendahuluan|Daftar\s+Isi|Kata\s+Pengantar|Glosarium|Lampiran|Profil|Indeks)(?:\b|$)',
      caseSensitive: false,
    );

    final List<String> words =
        cleanCurr.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    if (structural.hasMatch(cleanCurr) && words.length <= 15) return true;

    if (cleanCurr.endsWith(',')) return false;
    if (cleanCurr.endsWith('.') && !cleanCurr.endsWith('...')) return false;
    if (words.length > 12) return false;

    int capitalizedWords = 0;
    int validWords       = 0;

    for (String w in words) {
      final String alphaOnly = w.replaceAll(RegExp(r'^[^a-zA-Z]+'), '');
      if (alphaOnly.isNotEmpty) {
        validWords++;
        if (alphaOnly[0] == alphaOnly[0].toUpperCase()) capitalizedWords++;
      }
    }

    if (validWords == 0) return false;

    final bool isTitleCase = (capitalizedWords / validWords) >= 0.8;
    final bool isAllCaps   = cleanCurr == cleanCurr.toUpperCase() &&
        cleanCurr.contains(RegExp(r'[a-zA-Z]'));

    bool isNextCap = false;
    final String cleanNext = next.replaceAll(RegExp(r'^[^a-zA-Z]+'), '');
    if (cleanNext.isNotEmpty) {
      isNextCap = cleanNext[0] == cleanNext[0].toUpperCase();
    }

    return (isTitleCase || isAllCaps) && isNextCap;
  }

  static String _runOfflinePipeline(Map<String, dynamic> payload) {
    String rawText = payload['text'] as String;
    final Map<String, String> userCustomDict =
        (payload['customDict'] as Map<String, String>?) ?? {};

    rawText = _applyGenericOcrPatterns(rawText);
    rawText = _normalizeNumericPatterns(rawText);
    rawText = _normalizePunctuation(rawText);

    final Map<String, String> fullDict =
        OcrDictionary.buildFullDictionary(userCustomDictionary: userCustomDict);
    final List<MapEntry<RegExp, String>> compiledDict = [];
    fullDict.forEach((String pattern, String replacement) {
      try {
        compiledDict.add(
            MapEntry(RegExp(pattern, caseSensitive: true), replacement));
      } catch (_) {}
    });

    final List<String> lines        = rawText.split('\n');
    final List<String> cleanedLines = [];

    for (String line in lines) {
      String trimmed = line.trim();
      if (trimmed.isEmpty) {
        cleanedLines.add('');
        continue;
      }
      if (_reNoise.hasMatch(trimmed) && trimmed.length < 5) continue;

      for (final MapEntry<RegExp, String> entry in compiledDict) {
        trimmed = trimmed.replaceAll(entry.key, entry.value);
      }
      trimmed = trimmed.replaceAll(_reNoiseSymbols, '');
      trimmed = trimmed.replaceAllMapped(
          _reMidCapital, (Match match) => match.group(0)!.toLowerCase());
      cleanedLines.add(trimmed.trimRight());
    }

    final StringBuffer reconstructed = StringBuffer();
    for (int i = 0; i < cleanedLines.length; i++) {
      final String curr = cleanedLines[i];
      if (curr.isEmpty) {
        reconstructed.write('\n\n');
        continue;
      }

      if (curr.endsWith('-') &&
          i < cleanedLines.length - 1 &&
          cleanedLines[i + 1].isNotEmpty) {
        reconstructed.write(curr.substring(0, curr.length - 1));
        continue;
      }

      reconstructed.write(curr);

      if (i < cleanedLines.length - 1) {
        final String next = cleanedLines[i + 1];
        if (next.isNotEmpty) {
          if (_reListBullet.hasMatch(next)) {
            reconstructed.write('\n\n');
          } else if (_isTitleCandidate(curr, next) || _isStrictTitle(curr)) {
            reconstructed.write('\n\n');
          } else if (!_rePuncEnd.hasMatch(curr) &&
              !_isStrictTitle(curr) &&
              !_isStrictTitle(next)) {
            reconstructed.write(' ');
          } else {
            reconstructed.write('\n');
          }
        }
      }
    }

    return reconstructed.toString().replaceAll(_reTripleNL, '\n\n').trim();
  }

  static double _calculateTextQualityIsolate(String text) {
    return OcrDictionary.calculateTextQuality(text);
  }

  static String _normalizeNumericPatterns(String text) {
    String res = text;
    res = res.replaceAllMapped(
        _reNumericRp,
        (Match m) => '${m.group(2)} rupiah'.replaceAll('.', ''));
    res = res.replaceAll('1/2', 'satu per dua');
    res = res.replaceAll('1/4', 'seperempat');
    res = res.replaceAll('3/4', 'tiga per empat');
    res = res.replaceAllMapped(_reNumericUnits, (Match m) {
      const Map<String, String> units = {
        'kg': 'kilogram', 'gr': 'gram', 'cm': 'sentimeter',
        'm':  'meter',    'km': 'kilometer',
      };
      return '${m.group(1)} ${units[m.group(2)]}';
    });
    return res;
  }

  static String _normalizePunctuation(String text) {
    String res = text;
    res = res.replaceAll(_rePuncSpaceComma, ',');
    res = res.replaceAll(_rePuncSpaceDot, '.');
    res = res.replaceAll(_rePuncMultiComma, ',');
    res = res.replaceAll(_rePuncMultiDot, '...');
    res = res.replaceAllMapped(
        _rePuncSpaceFix, (Match m) => '${m.group(1)} ${m.group(2)}');
    return res;
  }

  static Future<String> _runGeminiTextCorrectionPass({
    required String text,
    required bool cognitiveMode,
    required List<String> lowConfWords,
    bool isSecondPass = false,
  }) async {
    // FIX: gunakan cached model — tidak instantiate GenerativeModel baru tiap call
    final GenerativeModel model = _getGeminiModel();

    final String suspectContext = lowConfWords.isNotEmpty
        ? '\nKata-kata berikut terdeteksi OCR dengan kepercayaan rendah — '
            'prioritaskan koreksinya: ${lowConfWords.take(20).join(', ')}'
        : '';

    final String passNote = isSecondPass
        ? '\n[PASS KE-2: Fokus pada konsistensi kalimat dan sisa typo yang terlewat di pass pertama.]'
        : '';

    final String modeInstruction = cognitiveMode
        ? '''
Kamu adalah pakar koreksi teks Bahasa Indonesia pasca-OCR dengan mode kognitif aktif.
$passNote
$_fewShotExamples
TUGASMU:
1. Perbaiki SEMUA typo OCR pada setiap kata di setiap kalimat. Hati-hati dengan pola a->g/q dan rn->m.
2. Perbaiki kalimat pasif menjadi aktif jika konteks memungkinkan.
3. Normalisasi kapitalisasi: teks ALL CAPS tanpa alasan → ubah ke kalimat normal.
4. Pastikan setiap kalimat terbaca alami dalam Bahasa Indonesia.
5. JANGAN mengubah nama orang, nama tempat, atau istilah khusus.
6. PERTAHANKAN struktur paragraf dan tag <PAGE_BREAK>.
7. Output WAJIB dalam Bahasa Indonesia.
$suspectContext'''
        : '''
Kamu adalah mesin koreksi teks OCR Bahasa Indonesia presisi tinggi.
$passNote
$_fewShotExamples
ATURAN MUTLAK:
1. Perbaiki SEMUA typo OCR pada setiap kata. Hati-hati dengan pola a->g/q dan rn->m.
2. Koreksi setiap kalimat yang tidak terbaca wajar akibat kesalahan OCR.
3. DILARANG KERAS: merangkum, menambah konten, menghilangkan kalimat, atau mengubah makna.
4. PERTAHANKAN persis: struktur paragraf, baris baru, tag <PAGE_BREAK>.
5. Jumlah kata output harus sangat mendekati input (toleransi 10 persen).
6. Output WAJIB dalam Bahasa Indonesia.
$suspectContext''';

    final String prompt = '''
$modeInstruction

Berikan HANYA teks yang sudah diperbaiki — tanpa penjelasan, tanpa markdown, tanpa preamble.

=== TEKS OCR ===
$text
=== AKHIR TEKS ===
''';

    final response = await model
        .generateContent([Content.text(prompt)])
        .timeout(const Duration(seconds: _OcrConfig.aiTimeoutSeconds));

    return _cleanAiOutput(response.text ?? text, text);
  }

  static String _cleanAiOutput(String aiText, String fallback) {
    String cleaned = aiText.trim();
    cleaned = cleaned.replaceAll(_reAiMdStart, '');
    cleaned = cleaned.replaceAll(_reAiMdEnd, '');
    cleaned = cleaned.replaceAll(_reAiPreamble, '');
    return cleaned.trim().isEmpty ? fallback : cleaned.trim();
  }

  static Map<String, dynamic> _validateAiOutputIsolate(
      Map<String, dynamic> data) {
    final String original    = (data['original'] as String?) ?? '';
    final String corrected   = (data['corrected'] as String?) ?? '';
    final bool cognitiveMode = (data['cognitiveMode'] as bool?) ?? false;
    final bool isLowQuality  = (data['isLowQuality'] as bool?) ?? false;

    if (corrected.isEmpty) return {'valid': false, 'reason': 'output_kosong'};

    final double lenMin  = isLowQuality ? _OcrConfig.lengthRatioMinLow    : _OcrConfig.lengthRatioMin;
    final double lenMax  = isLowQuality ? _OcrConfig.lengthRatioMaxLow    : _OcrConfig.lengthRatioMax;
    final double wordMin = isLowQuality ? _OcrConfig.wordRatioMinLow      : _OcrConfig.wordRatioMin;
    final double wordMax = isLowQuality ? _OcrConfig.wordRatioMaxLow      : _OcrConfig.wordRatioMax;
    final int    paraMax = isLowQuality ? _OcrConfig.maxParagraphDriftLow : _OcrConfig.maxParagraphDrift;
    final double hallucMax = cognitiveMode
        ? (_OcrConfig.hallucinationThreshold * 1.5)
        : (isLowQuality
            ? _OcrConfig.hallucinationThresholdLow
            : _OcrConfig.hallucinationThreshold);

    final double lenRatio = corrected.length / math.max(1, original.length);
    if (lenRatio < lenMin || lenRatio > lenMax)
      return {'valid': false, 'reason': 'panjang_karakter_berubah_drastis'};

    final List<String> origWords = original
        .split(_reEmptySpaces)
        .where((String w) => w.isNotEmpty)
        .toList();
    final List<String> corrWords = corrected
        .split(_reEmptySpaces)
        .where((String w) => w.isNotEmpty)
        .toList();
    final double wordRatio = corrWords.length / math.max(1, origWords.length);
    if (wordRatio < wordMin || wordRatio > wordMax)
      return {'valid': false, 'reason': 'jumlah_kata_berubah_drastis'};

    final double sim = _calculateSimilarityRatio(original, corrected);
    if ((1.0 - sim) > hallucMax)
      return {'valid': false, 'reason': 'terlalu_banyak_perubahan'};

    final int origParas = '\n\n'.allMatches(original).length;
    final int corrParas = '\n\n'.allMatches(corrected).length;
    if ((origParas - corrParas).abs() > paraMax)
      return {'valid': false, 'reason': 'paragraf_berubah'};

    return {'valid': true, 'reason': 'ok'};
  }

  static double _calculateSimilarityRatio(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final String a = s1.length > 1000 ? s1.substring(0, 1000) : s1;
    final String b = s2.length > 1000 ? s2.substring(0, 1000) : s2;

    Int32List v0 = Int32List(b.length + 1);
    Int32List v1 = Int32List(b.length + 1);

    for (int i = 0; i <= b.length; i++) v0[i] = i;

    for (int i = 0; i < a.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < b.length; j++) {
        final int cost = (a[i] == b[j]) ? 0 : 1;
        v1[j + 1] =
            math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= b.length; j++) v0[j] = v1[j];
    }
    return 1.0 - (v1[b.length] / math.max(a.length, b.length));
  }

  static ProcessedTextData buildTtsReadyOutput(String fullText) {
    if (fullText.isEmpty) return ProcessedTextData.empty();

    final List<String> rawPages               = fullText.split('<PAGE_BREAK>');
    final List<String> finalSentences         = [];
    final List<String> finalSyllabified       = [];
    final List<int>    sentenceToPageMap      = [];
    final List<int>    sentenceToParagraphMap = [];
    final List<List<int>> uiPages            = [];

    int globalSentenceIndex  = 0;
    int globalParagraphIndex = 0;

    for (int pageIndex = 0; pageIndex < rawPages.length; pageIndex++) {
      final List<String> paragraphs =
          rawPages[pageIndex].split(RegExp(r'\n{2,}'));
      final List<int> sentenceIndicesForThisPage = [];

      for (final String paragraph in paragraphs) {
        final String cleanParagraph = paragraph
            .replaceAll('\n', ' ')
            .replaceAll(_reEmptySpaces, ' ')
            .trim();
        if (cleanParagraph.isEmpty) continue;

        final List<String> rawSentences = cleanParagraph
            .split(_reSentenceSplitter)
            .map((String s) => s.trim())
            .where((String s) => s.length > 2)
            .toList();

        final List<String> breathGroups = _buildBreathGroups(rawSentences);

        for (final String sentence in breathGroups) {
          String cleanSentence =
              sentence.replaceAll(_reCleanSentenceStart, '').trim();
          if (cleanSentence.isEmpty) continue;

          if (cleanSentence == cleanSentence.toUpperCase() &&
              cleanSentence.length > 5) {
            cleanSentence = cleanSentence.substring(0, 1).toUpperCase() +
                cleanSentence.substring(1).toLowerCase();
          }

          if (!_rePuncEndPrev.hasMatch(cleanSentence)) cleanSentence += '.';

          finalSentences.add(cleanSentence);
          finalSyllabified.add(TextUtils.syllabifySentence(cleanSentence));
          sentenceToPageMap.add(pageIndex);
          sentenceToParagraphMap.add(globalParagraphIndex);
          sentenceIndicesForThisPage.add(globalSentenceIndex);
          globalSentenceIndex++;
        }
        globalParagraphIndex++;
      }

      if (sentenceIndicesForThisPage.isNotEmpty) {
        uiPages.add(sentenceIndicesForThisPage);
      }
    }

    return ProcessedTextData(
      fullRawText:            fullText,
      sentences:              finalSentences,
      syllabifiedSentences:   finalSyllabified,
      sentenceToPageMap:      sentenceToPageMap,
      sentenceToParagraphMap: sentenceToParagraphMap,
      pages:                  uiPages,
    );
  }

  static bool _isStrictTitle(String text) {
    final String clean = text.trim();
    if (clean.isEmpty) return false;
    if (clean.length > 60) return false;
    if (clean.endsWith('.') && !clean.endsWith('...')) return false;

    final words =
        clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length > 10) return false;

    final lettersOnly = clean.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (lettersOnly.isEmpty) return false;

    final upperCount =
        lettersOnly.replaceAll(RegExp(r'[^A-Z]'), '').length;
    final bool isMostlyCaps = upperCount / lettersOnly.length > 0.7;

    int capWords = 0;
    for (var w in words) {
      final alpha = w.replaceAll(RegExp(r'[^a-zA-Z]'), '');
      if (alpha.isNotEmpty && alpha[0] == alpha[0].toUpperCase()) capWords++;
    }
    final bool isTitleCase = capWords / words.length > 0.8;

    return isMostlyCaps || isTitleCase;
  }

  static List<String> _buildBreathGroups(List<String> fragments) {
    if (fragments.isEmpty) return [];

    const int maxWordsPerGroup = 15;
    const int minWordsToSplit  = 5;

    final List<String> groups = [];

    for (final String frag in fragments) {
      if (frag.isEmpty) continue;

      if (groups.isEmpty) {
        groups.add(frag);
        continue;
      }

      final String prev      = groups.last;
      final int    prevWords = prev.split(' ').length;
      final int    currWords = frag.split(' ').length;

      if (prevWords + currWords > maxWordsPerGroup) {
        groups.add(frag);
        continue;
      }

      if (_isStrictTitle(prev)) {
        groups.add(frag);
        continue;
      }

      if (prevWords < minWordsToSplit) {
        groups[groups.length - 1] = '$prev $frag';
        continue;
      }

      if (_reContinuationPattern.hasMatch(frag) ||
          _reDialogResponsePattern.hasMatch(frag)) {
        groups[groups.length - 1] = '$prev $frag';
        continue;
      }

      if (currWords <= 3) {
        groups[groups.length - 1] = '$prev $frag';
        continue;
      }

      groups.add(frag);
    }

    return groups;
  }

  static bool _shouldMergeFragment(String prev, String curr) {
    if (curr.isEmpty) return false;
    final List<String> prevWords = prev.split(' ');
    if (prevWords.length > 6) return false;
    if (_rePuncEndPrev.hasMatch(prev)) return false;
    if (_reContinuationPattern.hasMatch(curr)) return true;
    final List<String> currWords = curr.split(' ');
    if (currWords.length <= 2 && curr[0] == curr[0].toLowerCase()) return true;
    if (_reStartCapital.hasMatch(curr) && prevWords.length >= 3) return false;
    return false;
  }

  static Future<bool> _checkInternetConnection() async {
    final List<ConnectivityResult> result =
        await Connectivity().checkConnectivity();
    if (result.contains(ConnectivityResult.none)) return false;
    try {
      final List<InternetAddress> lookup =
          await InternetAddress.lookup('google.com');
      return lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}