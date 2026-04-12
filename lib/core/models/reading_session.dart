// ignore_for_file: constant_identifier_names, unintended_html_in_doc_comment, avoid_types_as_parameter_names

import 'package:cloud_firestore/cloud_firestore.dart';

enum WordStatus {
  correct,
  partially_correct,
  incorrect,
  missed,
}

class WordEvaluation {
  final String originalWord;
  final String spokenWord;
  final WordStatus status;

  const WordEvaluation({
    required this.originalWord,
    required this.spokenWord,
    required this.status,
  });

  Map<String, dynamic> toMap() => {
        'originalWord': originalWord,
        'spokenWord': spokenWord,
        'status': status.name,
      };

  factory WordEvaluation.fromMap(Map<String, dynamic> map) => WordEvaluation(
        originalWord: map['originalWord']?.toString() ?? '',
        spokenWord: map['spokenWord']?.toString() ?? '',
        status: WordStatus.values.firstWhere(
          (e) => e.name == map['status'],
          orElse: () => WordStatus.incorrect,
        ),
      );
}

class ReadingSession {
  final String? id;
  final String userId;
  final String bookId;
  final String bookTitle;
  final int sentenceIndex;
  final String originalText;
  final String spokenText;
  final double accuracyScore;
  final int wordCount;
  final int correctCount;
  final int partialCount;
  final int incorrectCount;
  final int missedCount;
  final int durationSeconds;
  final List<WordEvaluation> evaluationDetails;
  final DateTime? timestamp;

  const ReadingSession({
    this.id,
    required this.userId,
    required this.bookId,
    required this.bookTitle,
    required this.sentenceIndex,
    required this.originalText,
    required this.spokenText,
    required this.accuracyScore,
    required this.wordCount,
    required this.correctCount,
    required this.partialCount,
    required this.incorrectCount,
    required this.missedCount,
    required this.durationSeconds,
    required this.evaluationDetails,
    this.timestamp,
  });

  factory ReadingSession.fromEvaluation({
    required String userId,
    required String bookId,
    required String bookTitle,
    required int sentenceIndex,
    required String originalText,
    required String spokenText,
    required double accuracyScore,
    required List<WordEvaluation> evaluationDetails,
    int durationSeconds = 0,
  }) {
    int correct = 0, partial = 0, incorrect = 0, missed = 0;
    for (final e in evaluationDetails) {
      switch (e.status) {
        case WordStatus.correct:
          correct++;
          break;
        case WordStatus.partially_correct:
          partial++;
          break;
        case WordStatus.incorrect:
          incorrect++;
          break;
        case WordStatus.missed:
          missed++;
          break;
      }
    }

    return ReadingSession(
      userId: userId,
      bookId: bookId,
      bookTitle: bookTitle,
      sentenceIndex: sentenceIndex,
      originalText: originalText,
      spokenText: spokenText,
      accuracyScore: accuracyScore,
      wordCount: evaluationDetails.length,
      correctCount: correct,
      partialCount: partial,
      incorrectCount: incorrect,
      missedCount: missed,
      durationSeconds: durationSeconds,
      evaluationDetails: evaluationDetails,
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'bookId': bookId,
        'bookTitle': bookTitle,
        'sentenceIndex': sentenceIndex,
        'originalText': originalText,
        'spokenText': spokenText,
        'accuracyScore': accuracyScore,
        'wordCount': wordCount,
        'correctCount': correctCount,
        'partialCount': partialCount,
        'incorrectCount': incorrectCount,
        'missedCount': missedCount,
        'durationSeconds': durationSeconds,
        'evaluationDetails':
            evaluationDetails.map((e) => e.toMap()).toList(),
        'timestamp': FieldValue.serverTimestamp(),
      };

  factory ReadingSession.fromMap(Map<String, dynamic> map, String docId) {
    final ts = map['timestamp'];
    return ReadingSession(
      id: docId,
      userId: map['userId']?.toString() ?? '',
      bookId: map['bookId']?.toString() ?? '',
      bookTitle: map['bookTitle']?.toString() ?? 'Tanpa Judul',
      sentenceIndex: (map['sentenceIndex'] ?? 0).toInt(),
      originalText: map['originalText']?.toString() ?? '',
      spokenText: map['spokenText']?.toString() ?? '',
      accuracyScore: (map['accuracyScore'] ?? 0.0).toDouble(),
      wordCount: (map['wordCount'] ?? 0).toInt(),
      correctCount: (map['correctCount'] ?? 0).toInt(),
      partialCount: (map['partialCount'] ?? 0).toInt(),
      incorrectCount: (map['incorrectCount'] ?? 0).toInt(),
      missedCount: (map['missedCount'] ?? 0).toInt(),
      durationSeconds: (map['durationSeconds'] ?? 0).toInt(),
      // FIX: whereType<Map<String,dynamic>>() menggantikan `as Map<String,dynamic>`
      // cast keras — jika Firestore return elemen bertipe lain, item dilewati
      // alih-alih crash dengan _CastError
      evaluationDetails: (map['evaluationDetails'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((e) => WordEvaluation.fromMap(e))
          .toList(),
      timestamp: ts is Timestamp
          ? ts.toDate()
          : (ts is String ? DateTime.tryParse(ts) : null),
    );
  }
}

class CommonMistake {
  final String originalWord;
  final String spokenWord;
  final int occurrences;
  final WordStatus status;

  const CommonMistake({
    required this.originalWord,
    required this.spokenWord,
    required this.occurrences,
    required this.status,
  });

  Map<String, dynamic> toMap() => {
        'originalWord': originalWord,
        'spokenWord': spokenWord,
        'occurrences': occurrences,
        'status': status.name,
      };

  factory CommonMistake.fromMap(Map<String, dynamic> map) => CommonMistake(
        originalWord: map['originalWord']?.toString() ?? '',
        spokenWord: map['spokenWord']?.toString() ?? '',
        occurrences: (map['occurrences'] ?? 1).toInt(),
        status: WordStatus.values.firstWhere(
          (e) => e.name == map['status'],
          orElse: () => WordStatus.incorrect,
        ),
      );
}

class SentenceSummary {
  final int sentenceIndex;
  final String originalText;
  final double accuracyScore;
  final int wordCount;
  final int correctCount;
  final int incorrectCount;

  const SentenceSummary({
    required this.sentenceIndex,
    required this.originalText,
    required this.accuracyScore,
    required this.wordCount,
    required this.correctCount,
    required this.incorrectCount,
  });

  Map<String, dynamic> toMap() => {
        'sentenceIndex': sentenceIndex,
        'originalText': originalText,
        'accuracyScore': accuracyScore,
        'wordCount': wordCount,
        'correctCount': correctCount,
        'incorrectCount': incorrectCount,
      };

  factory SentenceSummary.fromMap(Map<String, dynamic> map) => SentenceSummary(
        sentenceIndex: (map['sentenceIndex'] ?? 0).toInt(),
        originalText: map['originalText']?.toString() ?? '',
        accuracyScore: (map['accuracyScore'] ?? 0.0).toDouble(),
        wordCount: (map['wordCount'] ?? 0).toInt(),
        correctCount: (map['correctCount'] ?? 0).toInt(),
        incorrectCount: (map['incorrectCount'] ?? 0).toInt(),
      );
}

class PracticeSummary {
  final String? id;
  final String userId;
  final String bookId;
  final String bookTitle;
  final int totalSentencesPracticed;
  final int totalSentencesInBook;
  final double avgAccuracy;
  final double highestAccuracy;
  final double lowestAccuracy;
  final int bestSentenceIndex;
  final int worstSentenceIndex;
  final int totalDurationSeconds;
  final List<SentenceSummary> sentenceBreakdown;
  final List<CommonMistake> commonMistakes;
  final int totalWordsRead;
  final int totalCorrect;
  final int totalPartial;
  final int totalIncorrect;
  final int totalMissed;
  final DateTime? timestamp;

  const PracticeSummary({
    this.id,
    required this.userId,
    required this.bookId,
    required this.bookTitle,
    required this.totalSentencesPracticed,
    required this.totalSentencesInBook,
    required this.avgAccuracy,
    required this.highestAccuracy,
    required this.lowestAccuracy,
    required this.bestSentenceIndex,
    required this.worstSentenceIndex,
    required this.totalDurationSeconds,
    required this.sentenceBreakdown,
    required this.commonMistakes,
    required this.totalWordsRead,
    required this.totalCorrect,
    required this.totalPartial,
    required this.totalIncorrect,
    required this.totalMissed,
    this.timestamp,
  });

  factory PracticeSummary.compute({
    required String userId,
    required String bookId,
    required String bookTitle,
    required int totalSentencesInBook,
    required Map<int, List<WordEvaluation>> allEvaluations,
    required Map<int, String> sentenceTexts,
    int totalDurationSeconds = 0,
  }) {
    if (allEvaluations.isEmpty) {
      return PracticeSummary(
        userId: userId,
        bookId: bookId,
        bookTitle: bookTitle,
        totalSentencesPracticed: 0,
        totalSentencesInBook: totalSentencesInBook,
        avgAccuracy: 0,
        highestAccuracy: 0,
        lowestAccuracy: 0,
        bestSentenceIndex: 0,
        worstSentenceIndex: 0,
        totalDurationSeconds: totalDurationSeconds,
        sentenceBreakdown: [],
        commonMistakes: [],
        totalWordsRead: 0,
        totalCorrect: 0,
        totalPartial: 0,
        totalIncorrect: 0,
        totalMissed: 0,
      );
    }

    final List<SentenceSummary> breakdown = [];
    double sumAccuracy = 0;
    double highest = 0;
    double lowest = 100;
    int bestIdx = 0;
    int worstIdx = 0;
    int tWords = 0, tCorrect = 0, tPartial = 0, tIncorrect = 0, tMissed = 0;

    final Map<String, Map<String, int>> mistakeMap = {};
    // FIX: simpan status per (originalWord, spokenWord) agar CommonMistake.status
    // mencerminkan tipe kesalahan yang benar — sebelumnya semua di-set incorrect
    // termasuk kata yang partially_correct
    final Map<String, Map<String, WordStatus>> mistakeStatusMap = {};

    allEvaluations.forEach((idx, evals) {
      int correct = 0, partial = 0, incorrect = 0, missed = 0;

      for (final e in evals) {
        switch (e.status) {
          case WordStatus.correct:
            correct++;
            break;
          case WordStatus.partially_correct:
            partial++;
            mistakeMap
                .putIfAbsent(e.originalWord, () => {})
                .update(e.spokenWord, (v) => v + 1, ifAbsent: () => 1);
            mistakeStatusMap
                .putIfAbsent(e.originalWord, () => {})[e.spokenWord] =
                WordStatus.partially_correct;
            break;
          case WordStatus.incorrect:
            incorrect++;
            mistakeMap
                .putIfAbsent(e.originalWord, () => {})
                .update(e.spokenWord, (v) => v + 1, ifAbsent: () => 1);
            mistakeStatusMap
                .putIfAbsent(e.originalWord, () => {})[e.spokenWord] =
                WordStatus.incorrect;
            break;
          case WordStatus.missed:
            missed++;
            mistakeMap
                .putIfAbsent(e.originalWord, () => {})
                .update('(terlewat)', (v) => v + 1, ifAbsent: () => 1);
            mistakeStatusMap
                .putIfAbsent(e.originalWord, () => {})['(terlewat)'] =
                WordStatus.missed;
            break;
        }
      }

      final double accuracy = evals.isEmpty
          ? 0
          : ((correct + partial * 0.5) / evals.length) * 100;

      sumAccuracy += accuracy;
      tWords += evals.length;
      tCorrect += correct;
      tPartial += partial;
      tIncorrect += incorrect;
      tMissed += missed;

      if (accuracy > highest) {
        highest = accuracy;
        bestIdx = idx;
      }
      if (accuracy < lowest) {
        lowest = accuracy;
        worstIdx = idx;
      }

      breakdown.add(SentenceSummary(
        sentenceIndex: idx,
        originalText: sentenceTexts[idx] ?? '',
        accuracyScore: accuracy,
        wordCount: evals.length,
        correctCount: correct,
        incorrectCount: incorrect + missed,
      ));
    });

    final List<CommonMistake> mistakes = [];
    mistakeMap.forEach((originalWord, spokenMap) {
      spokenMap.forEach((spokenWord, count) {
        mistakes.add(CommonMistake(
          originalWord: originalWord,
          spokenWord: spokenWord,
          occurrences: count,
          // FIX: ambil status dari mistakeStatusMap — bukan hardcode incorrect
          status: mistakeStatusMap[originalWord]?[spokenWord] ??
              WordStatus.incorrect,
        ));
      });
    });
    mistakes.sort((a, b) => b.occurrences.compareTo(a.occurrences));
    breakdown.sort((a, b) => a.sentenceIndex.compareTo(b.sentenceIndex));

    return PracticeSummary(
      userId: userId,
      bookId: bookId,
      bookTitle: bookTitle,
      totalSentencesPracticed: allEvaluations.length,
      totalSentencesInBook: totalSentencesInBook,
      avgAccuracy: sumAccuracy / allEvaluations.length,
      highestAccuracy: highest,
      lowestAccuracy: lowest,
      bestSentenceIndex: bestIdx,
      worstSentenceIndex: worstIdx,
      totalDurationSeconds: totalDurationSeconds,
      sentenceBreakdown: breakdown,
      commonMistakes: mistakes.take(10).toList(),
      totalWordsRead: tWords,
      totalCorrect: tCorrect,
      totalPartial: tPartial,
      totalIncorrect: tIncorrect,
      totalMissed: tMissed,
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'bookId': bookId,
        'bookTitle': bookTitle,
        'totalSentencesPracticed': totalSentencesPracticed,
        'totalSentencesInBook': totalSentencesInBook,
        'avgAccuracy': avgAccuracy,
        'highestAccuracy': highestAccuracy,
        'lowestAccuracy': lowestAccuracy,
        'bestSentenceIndex': bestSentenceIndex,
        'worstSentenceIndex': worstSentenceIndex,
        'totalDurationSeconds': totalDurationSeconds,
        'sentenceBreakdown': sentenceBreakdown.map((e) => e.toMap()).toList(),
        'commonMistakes': commonMistakes.map((e) => e.toMap()).toList(),
        'totalWordsRead': totalWordsRead,
        'totalCorrect': totalCorrect,
        'totalPartial': totalPartial,
        'totalIncorrect': totalIncorrect,
        'totalMissed': totalMissed,
        'completionRate': totalSentencesInBook > 0
            ? (totalSentencesPracticed / totalSentencesInBook) * 100
            : 0.0,
        'timestamp': FieldValue.serverTimestamp(),
      };

  factory PracticeSummary.fromMap(Map<String, dynamic> map, String docId) {
    final ts = map['timestamp'];
    return PracticeSummary(
      id: docId,
      userId: map['userId']?.toString() ?? '',
      bookId: map['bookId']?.toString() ?? '',
      bookTitle: map['bookTitle']?.toString() ?? 'Tanpa Judul',
      totalSentencesPracticed: (map['totalSentencesPracticed'] ?? 0).toInt(),
      totalSentencesInBook: (map['totalSentencesInBook'] ?? 0).toInt(),
      avgAccuracy: (map['avgAccuracy'] ?? 0.0).toDouble(),
      highestAccuracy: (map['highestAccuracy'] ?? 0.0).toDouble(),
      lowestAccuracy: (map['lowestAccuracy'] ?? 0.0).toDouble(),
      bestSentenceIndex: (map['bestSentenceIndex'] ?? 0).toInt(),
      worstSentenceIndex: (map['worstSentenceIndex'] ?? 0).toInt(),
      totalDurationSeconds: (map['totalDurationSeconds'] ?? 0).toInt(),
      // FIX: whereType<Map<String,dynamic>>() — skip elemen invalid, tidak crash
      sentenceBreakdown: (map['sentenceBreakdown'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((e) => SentenceSummary.fromMap(e))
          .toList(),
      commonMistakes: (map['commonMistakes'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((e) => CommonMistake.fromMap(e))
          .toList(),
      totalWordsRead: (map['totalWordsRead'] ?? 0).toInt(),
      totalCorrect: (map['totalCorrect'] ?? 0).toInt(),
      totalPartial: (map['totalPartial'] ?? 0).toInt(),
      totalIncorrect: (map['totalIncorrect'] ?? 0).toInt(),
      totalMissed: (map['totalMissed'] ?? 0).toInt(),
      timestamp: ts is Timestamp
          ? ts.toDate()
          : (ts is String ? DateTime.tryParse(ts) : null),
    );
  }
}