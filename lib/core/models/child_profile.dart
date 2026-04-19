import 'package:cloud_firestore/cloud_firestore.dart';

class ChildProfile {
  final String userId;
  final String name;
  final int age;
  final String gender; // 'L' atau 'P'
  final String grade;  // 'SD 1'–'SD 6', 'SMP 1'–'SMP 3', 'SMA 1'–'SMA 3'
  final String dyslexiaType; // 'Ringan', 'Sedang', 'Berat', 'Belum Tahu'
  final bool isProfileComplete;
  
  // Penambahan Field Role & Pendampingan Guru
  final String accountType; // 'managed' atau 'independent'
  final String? createdBy;  // UID Guru yang membuat (jika managed)
  final List<String> linkedTeacher; // Array UID Guru pendamping

  const ChildProfile({
    required this.userId,
    required this.name,
    required this.age,
    required this.gender,
    required this.grade,
    required this.dyslexiaType,
    this.isProfileComplete = false,
    this.accountType = 'independent',
    this.createdBy,
    this.linkedTeacher = const [],
  });

  ChildProfile copyWith({
    String? userId,
    String? name,
    int? age,
    String? gender,
    String? grade,
    String? dyslexiaType,
    bool? isProfileComplete,
    String? accountType,
    String? createdBy,
    List<String>? linkedTeacher,
  }) {
    return ChildProfile(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      grade: grade ?? this.grade,
      dyslexiaType: dyslexiaType ?? this.dyslexiaType,
      isProfileComplete: isProfileComplete ?? this.isProfileComplete,
      accountType: accountType ?? this.accountType,
      createdBy: createdBy ?? this.createdBy,
      linkedTeacher: linkedTeacher ?? this.linkedTeacher,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'displayName': name,
      'age': age,
      'gender': gender,
      'grade': grade,
      'dyslexiaType': dyslexiaType,
      'isProfileComplete': isProfileComplete,
      'accountType': accountType,
      'createdBy': createdBy ?? '',
      'linkedTeacher': linkedTeacher,
      'lastUpdated': FieldValue.serverTimestamp(),
    };
  }

  factory ChildProfile.fromMap(Map<String, dynamic> map, String uid) {
    return ChildProfile(
      userId: uid,
      name: map['displayName']?.toString() ?? '',
      age: (map['age'] ?? 0).toInt(),
      gender: map['gender']?.toString() ?? 'L',
      grade: map['grade']?.toString() ?? 'SD 1',
      dyslexiaType: map['dyslexiaType']?.toString() ?? 'Belum Tahu',
      isProfileComplete: map['isProfileComplete'] ?? false,
      accountType: map['accountType']?.toString() ?? 'independent',
      createdBy: map['createdBy']?.toString(),
      linkedTeacher: List<String>.from(map['linkedTeacher'] ?? []),
    );
  }
}