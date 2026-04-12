// ignore_for_file: unused_field

class SyllableSegment {
  final String text;
  final bool isEven;

  const SyllableSegment({required this.text, required this.isEven});
}

class WordSegment {
  final String raw;
  final bool isWord;
  final List<SyllableSegment> syllables;

  const WordSegment({
    required this.raw,
    required this.isWord,
    this.syllables = const [],
  });
}

class TextUtils {
  static final RegExp _digraph   = RegExp(r'^(ny|ng|sy|kh)$', caseSensitive: false);
  static final RegExp _diphthong = RegExp(r'^(ai|au|oi)$',    caseSensitive: false);

  static final RegExp _tokenizer =
      RegExp(r'[a-zA-ZÀ-öø-ÿ0-9]+|[^a-zA-ZÀ-öø-ÿ0-9]+');

  static final RegExp _reWordChar    = RegExp(r'[a-zA-ZÀ-öø-ÿ]');
  static final RegExp _reNumericOnly = RegExp(r'^\d+$');

  // ── Pola pemenggalan (static final — tidak alokasikan RegExp baru tiap panggilan)
  //
  // Urutan eksekusi: D → B (iteratif) → A (iteratif) → C (iteratif)
  // D sebelum B agar triple konsonan ditangani lebih dulu,
  // B sebelum A agar pola lebih spesifik dikonsumsi duluan.

  // Pola A: V-C-V atau V-digraf-V
  //   "makan" a-k-a → "ma-kan",  "bunga" u-ng-a → "bu-nga"
  static final RegExp _patA = RegExp(
    r'([aiueoAIUEOéÉ])(ny|ng|sy|kh|[b-df-hj-np-tv-zB-DF-HJ-NP-TV-Z])([aiueoAIUEOéÉ])',
  );

  // Pola B: V-CC-V (dua konsonan tunggal)
  //   "april" a-p-r-i → "ap-ril",  "berlomba" o-m-b-a → "om-ba"
  static final RegExp _patB = RegExp(
    r'([aiueoAIUEOéÉ])([b-df-hj-np-tv-zB-DF-HJ-NP-TV-Z])([b-df-hj-np-tv-zB-DF-HJ-NP-TV-Z])([aiueoAIUEOéÉ])',
  );

  // Pola C: V-V bukan diftong
  //   "doa" o-a → "do-a",  "sungai" a-i → tetap (diftong)
  static final RegExp _patC = RegExp(r'([aiueoAIUEOéÉ])([aiueoAIUEOéÉ])');

  // Pola D: V-CCC-V (triple konsonan) — split setelah konsonan pertama
  //   "instruksi" i-n-s-t-r-u → "ins-truk-si"
  static final RegExp _patD = RegExp(
    r'([aiueoAIUEOéÉ])([b-df-hj-np-tv-zB-DF-HJ-NP-TV-Z])([b-df-hj-np-tv-zB-DF-HJ-NP-TV-Z])([b-df-hj-np-tv-zB-DF-HJ-NP-TV-Z])([aiueoAIUEOéÉ])',
  );

  static String syllabifySentence(String text) {
    if (text.isEmpty) return text;
    final words  = text.split(' ');
    final buffer = StringBuffer();
    for (int i = 0; i < words.length; i++) {
      buffer.write(_syllabifyWord(words[i]));
      if (i < words.length - 1) buffer.write(' ');
    }
    return buffer.toString();
  }

  static String syllabifyForSpeech(String text) {
    if (text.isEmpty) return text;
    return syllabifySentence(text).replaceAll('-', ', ');
  }

  static List<WordSegment> tokenizeWords(String text) {
    if (text.isEmpty) return [];

    final List<WordSegment> result = [];
    final Iterable<RegExpMatch> tokens = _tokenizer.allMatches(text);

    for (final match in tokens) {
      final String token = match.group(0)!;
      final bool isWord  = _reWordChar.hasMatch(token);

      if (!isWord || token.length <= 1) {
        result.add(WordSegment(raw: token, isWord: false));
        continue;
      }

      final String syllabified           = _syllabifyWord(token);
      final List<String> parts           = syllabified.split('-');
      final List<SyllableSegment> segments = [];

      for (int i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) {
          segments.add(SyllableSegment(text: parts[i], isEven: i.isEven));
        }
      }

      result.add(WordSegment(raw: token, isWord: true, syllables: segments));
    }

    return result;
  }

  static String _syllabifyWord(String word) {
    // FIX: cutoff <= 2 bukan <= 3 — kata 3 huruf seperti "dia","tua","doa"
    // mengandung dua suku kata dan harus diproses (di-a, tu-a, do-a)
    if (word.length <= 2 || _reNumericOnly.hasMatch(word)) return word;

    String result = word;

    // ── Langkah 1: Triple konsonan (Pola D) ──────────────────────────────────
    result = result.replaceAllMapped(_patD,
        (m) => '${m[1]}${m[2]}-${m[3]}${m[4]}${m[5]}');

    // ── Langkah 2: Dua konsonan (Pola B) — iteratif ──────────────────────────
    // Iteratif karena replaceAllMapped non-overlapping: vokal akhir match
    // dikonsumsi sehingga V-CC-V berikutnya butuh pass baru.
    String prev = '';
    while (prev != result) {
      prev   = result;
      result = result.replaceAllMapped(_patB, (m) {
        final String pair = '${m[2]}${m[3]}';
        if (_digraph.hasMatch(pair)) {
          return '${m[1]}-${m[2]}${m[3]}${m[4]}';
        }
        return '${m[1]}${m[2]}-${m[3]}${m[4]}';
      });
    }

    // ── Langkah 3: Satu konsonan / digraf (Pola A) — iteratif ────────────────
    // Root cause fix utama: versi lama hanya satu pass sehingga kata seperti
    // "sekolah" hanya menghasilkan "se-kolah" bukan "se-ko-lah", karena vokal
    // 'o' dikonsumsi match "eko" dan "ola" tidak pernah ketemu.
    // Dengan iteratif: pass 1 → "se-kolah", pass 2 → "se-ko-lah" ✓
    prev = '';
    while (prev != result) {
      prev   = result;
      result = result.replaceAllMapped(
          _patA, (m) => '${m[1]}-${m[2]}${m[3]}');
    }

    // ── Langkah 4: Dua vokal berurutan (Pola C) — iteratif ───────────────────
    prev = '';
    while (prev != result) {
      prev   = result;
      result = result.replaceAllMapped(_patC, (m) {
        final String pair = '${m[1]}${m[2]}';
        if (_diphthong.hasMatch(pair)) return pair;
        return '${m[1]}-${m[2]}';
      });
    }

    // ── Cleanup ───────────────────────────────────────────────────────────────
    result = result.replaceAll('--', '-');
    if (result.startsWith('-')) result = result.substring(1);
    if (result.endsWith('-'))   result = result.substring(0, result.length - 1);

    return result;
  }
}