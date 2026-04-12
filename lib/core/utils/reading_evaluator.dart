// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:math';
import '../models/reading_session.dart';

class ReadingEvaluator {
  // FIX: pre-compile RegExp sebagai static final — tidak dibuat ulang tiap _cleanAndSplit dipanggil
  static final RegExp _rePunctuation = RegExp(r'[^\w\s]');
  static final RegExp _reWhitespace  = RegExp(r'\s+');

  static List<WordEvaluation> evaluateReading(String original, String spoken) {
    final cleanOriginal = _cleanAndSplit(original);
    final cleanSpoken   = _cleanAndSplit(spoken);

    final List<WordEvaluation> results = [];
    int spokenIndex = 0;

    for (int i = 0; i < cleanOriginal.length; i++) {
      final origWord = cleanOriginal[i];

      if (spokenIndex >= cleanSpoken.length) {
        results.add(WordEvaluation(
          originalWord: origWord,
          spokenWord:   '',
          status:       WordStatus.missed,
        ));
        continue;
      }

      final spkWord   = cleanSpoken[spokenIndex];
      final double similarity = _calculateSimilarity(origWord, spkWord);

      if (similarity == 1.0) {
        results.add(WordEvaluation(
          originalWord: origWord,
          spokenWord:   spkWord,
          status:       WordStatus.correct,
        ));
        spokenIndex++;
      } else if (similarity >= 0.5) {
        results.add(WordEvaluation(
          originalWord: origWord,
          spokenWord:   spkWord,
          status:       WordStatus.partially_correct,
        ));
        spokenIndex++;
      } else {
        bool foundMatchAhead = false;
        for (int lookAhead = 1; lookAhead <= 2; lookAhead++) {
          if (spokenIndex + lookAhead < cleanSpoken.length) {
            final double nextSimilarity =
                _calculateSimilarity(origWord, cleanSpoken[spokenIndex + lookAhead]);
            if (nextSimilarity >= 0.5) {
              results.add(WordEvaluation(
                originalWord: origWord,
                spokenWord:   cleanSpoken[spokenIndex + lookAhead],
                status: nextSimilarity == 1.0
                    ? WordStatus.correct
                    : WordStatus.partially_correct,
              ));
              spokenIndex      += lookAhead + 1;
              foundMatchAhead   = true;
              break;
            }
          }
        }

        if (!foundMatchAhead) {
          results.add(WordEvaluation(
            originalWord: origWord,
            spokenWord:   spkWord,
            status:       WordStatus.incorrect,
          ));
        }
      }
    }

    return results;
  }

  static double calculateOverallAccuracy(List<WordEvaluation> evaluations) {
    if (evaluations.isEmpty) return 0.0;
    double totalScore = 0.0;
    for (final eval in evaluations) {
      if (eval.status == WordStatus.correct) totalScore += 1.0;
      else if (eval.status == WordStatus.partially_correct) totalScore += 0.5;
    }
    return (totalScore / evaluations.length) * 100.0;
  }

  static List<String> _cleanAndSplit(String text) {
    // FIX: gunakan static final RegExp — tidak alokasikan RegExp baru tiap panggilan
    final cleanText = text.replaceAll(_rePunctuation, '').toLowerCase();
    return cleanText
        .split(_reWhitespace)
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static double _calculateSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    final int maxLength = max(s1.length, s2.length);
    if (maxLength == 0) return 1.0;
    return 1.0 - (_levenshteinDistance(s1, s2) / maxLength);
  }

  // FIX: rolling array (2×1D List<int>) menggantikan 2D matrix List<List<int>>
  // Sebelumnya alokasi (s1.len+1)×(s2.len+1) int per pasang kata,
  // dipanggil untuk setiap kata di setiap kalimat evaluasi.
  // Rolling array hanya alokasi 2×(s2.len+1) int — jauh lebih ringan.
  static int _levenshteinDistance(String s1, String s2) {
    List<int> v0 = List<int>.generate(s2.length + 1, (j) => j);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        final int cost = s1[i] == s2[j] ? 0 : 1;
        v1[j + 1] = min(
          min(v1[j] + 1, v0[j + 1] + 1),
          v0[j] + cost,
        );
      }
      final List<int> temp = v0;
      v0 = v1;
      v1 = temp;
    }

    return v0[s2.length];
  }
}