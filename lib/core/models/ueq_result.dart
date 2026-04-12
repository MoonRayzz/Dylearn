import 'package:cloud_firestore/cloud_firestore.dart';

class UeqResult {
  final String id;
  final String userId;
  final String childName;
  final DateTime timestamp;
  final String docId; // Dokumen apa yang baru saja dibaca
  final Map<String, int> answers; // Key: 'q1', Value: 2
  final int totalScore;

  // 1. Menggunakan const constructor untuk potensi optimasi kompilasi
  const UeqResult({
    required this.id,
    required this.userId,
    required this.childName,
    required this.timestamp,
    required this.docId,
    required this.answers,
    required this.totalScore,
  });

  // 2. Fitur copyWith untuk efisiensi update state (tanpa membuat objek dari nol)
  UeqResult copyWith({
    String? id,
    String? userId,
    String? childName,
    DateTime? timestamp,
    String? docId,
    Map<String, int>? answers,
    int? totalScore,
  }) {
    return UeqResult(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      childName: childName ?? this.childName,
      timestamp: timestamp ?? this.timestamp,
      docId: docId ?? this.docId,
      answers: answers ?? this.answers,
      totalScore: totalScore ?? this.totalScore,
    );
  }

  // Konversi ke Map untuk Firebase
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'childName': childName,
      'timestamp': Timestamp.fromDate(timestamp),
      'docId': docId,
      'answers': answers,
      'totalScore': totalScore,
    };
  }

  // 3. Konversi dari Firebase dengan Safe Parsing (Anti-Crash)
  factory UeqResult.fromMap(String id, Map<String, dynamic> map) {
    // Handling aman untuk timestamp:
    // Jika null (masalah latensi), gunakan waktu sekarang agar tidak crash
    final timestampData = map['timestamp'];
    DateTime parsedDate;
    if (timestampData is Timestamp) {
      parsedDate = timestampData.toDate();
    } else if (timestampData is String) {
      // Backup jika tersimpan sebagai string ISO8601
      parsedDate = DateTime.tryParse(timestampData) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    // Handling aman untuk Map answers:
    // Pastikan casting ke <String, int> berhasil meskipun data di Firestore bertipe dynamic
    Map<String, int> parsedAnswers = {};
    if (map['answers'] != null && map['answers'] is Map) {
      // Menggunakan Map.from untuk memastikan tipe data benar-benar String:int
      // Menggunakan try-catch block kecil atau casting aman
      final rawMap = map['answers'] as Map;
      parsedAnswers = rawMap.map((key, value) => MapEntry(
            key.toString(), 
            (value is num) ? value.toInt() : 0, // Cegah error jika value double
          ));
    }

    return UeqResult(
      id: id,
      userId: map['userId']?.toString() ?? '',
      childName: map['childName']?.toString() ?? 'Anak',
      timestamp: parsedDate,
      docId: map['docId']?.toString() ?? '',
      answers: parsedAnswers,
      // Pastikan totalScore selalu integer, bahkan jika Firestore mengirim double
      totalScore: (map['totalScore'] is num) 
          ? (map['totalScore'] as num).toInt() 
          : 0,
    );
  }
}