// ignore_for_file: avoid_print, curly_braces_in_flow_control_structures, unnecessary_cast

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class SyncPreviewData {
  final String managedUid;
  final String pairingCode;
  final String managedName;
  final int    managedAge;
  final String managedGender;
  final String managedGrade;
  final String managedDyslexiaType;
  final List<String> managedLinkedTeacher;
  final String currentName;
  final int    currentAge;
  final String currentGender;
  final String currentGrade;
  final String currentDyslexiaType;
  final int    totalBooks;

  const SyncPreviewData({
    required this.managedUid,
    required this.pairingCode,
    required this.managedName,
    required this.managedAge,
    required this.managedGender,
    required this.managedGrade,
    required this.managedDyslexiaType,
    required this.managedLinkedTeacher,
    required this.currentName,
    required this.currentAge,
    required this.currentGender,
    required this.currentGrade,
    required this.currentDyslexiaType,
    required this.totalBooks,
  });

  bool get hasProfileDiff =>
      managedName         != currentName         ||
      managedAge          != currentAge          ||
      managedGender       != currentGender       ||
      managedGrade        != currentGrade        ||
      managedDyslexiaType != currentDyslexiaType;
}

class AuthService {
  final FirebaseAuth      _auth         = FirebaseAuth.instance;
  final FirebaseFirestore _firestore    = FirebaseFirestore.instance;
  final GoogleSignIn      _googleSignIn = GoogleSignIn();

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<User?> registerWithEmail(
      String email, String password, String name) async {
    try {
      final result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      final user = result.user;
      if (user != null) {
        await Future.wait([
          user.updateDisplayName(name),
          _saveUserToFirestore(user, 'email',
              customName: name, isFinalized: true),
        ]);
        await user.reload();
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  Future<User?> loginWithEmail(String email, String password) async {
    try {
      final result = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      if (result.user != null) {
        await _saveUserToFirestore(result.user!, 'email');
        await _firestore.collection('users').doc(result.user!.uid).set(
            {'lastLogin': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
      }
      return result.user;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<User?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;
      final googleAuth     = await googleUser.authentication;
      final credential     = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
      final userCredential = await _auth.signInWithCredential(credential);
      if (userCredential.user != null) {
        await _saveUserToFirestore(userCredential.user!, 'google.com',
            isFinalized: true);
        await _firestore.collection('users').doc(userCredential.user!.uid).set(
            {'lastLogin': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
      }
      return userCredential.user;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw Exception("Gagal login Google: $e");
    }
  }

  Future<void> signOut() async {
    await Future.wait([_googleSignIn.signOut(), _auth.signOut()]);
  }

  Future<void> _saveUserToFirestore(User user, String provider,
      {String? customName, bool isFinalized = false}) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    final doc     = await userRef.get();
    final data    = doc.data();

    // Jika document belum ada, atau hanya ada field 'lastLogin' (tidak ada 'role' dll), kita isi field wajibnya
    if (!doc.exists || (data != null && !data.containsKey('role'))) {
      await userRef.set({
        'uid':               user.uid,
        'email':             user.email ?? '',
        'displayName':       customName ?? user.displayName ?? 'User',
        'photoUrl':          user.photoURL ?? '',
        'createdAt':         FieldValue.serverTimestamp(),
        'lastLogin':         FieldValue.serverTimestamp(),
        'provider':          provider,
        'isNameFinalized':   isFinalized,
        'role':              'user',
        'accountType':       'independent',
        'linkedTeacher':     [],
        'isProfileComplete': false,
        'age':               0,
        'gender':            '',
        'grade':             '',
        'dyslexiaType':      '',
      }, SetOptions(merge: true));
    }
  }

  Future<void> createManagedStudent({
    required String teacherUid,
    required String name,
    required int    age,
    required String gender,
    required String grade,
    required String dyslexiaType,
  }) async {
    try {
      final docRef = _firestore.collection('users').doc();
      final code   = _generatePairingCode(docRef.id);
      await docRef.set({
        'uid':               docRef.id,
        'email':             '',
        'displayName':       name,
        'photoUrl':          '',
        'createdAt':         FieldValue.serverTimestamp(),
        'lastLogin':         FieldValue.serverTimestamp(),
        'provider':          'managed',
        'role':              'user',
        'accountType':       'managed',
        'createdBy':         teacherUid,
        'linkedTeacher':     [teacherUid],
        'isProfileComplete': true,
        'age':               age,
        'gender':            gender,
        'grade':             grade,
        'dyslexiaType':      dyslexiaType,
        'pairingCode':       code,
        'isSyncPending':     true,
      });
    } catch (e) {
      throw Exception("Gagal membuat data murid: $e");
    }
  }

  String _generatePairingCode(String docId) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final seed  = docId.hashCode.abs();
    String code = 'DYL-';
    for (int i = 0; i < 6; i++) code += chars[(seed >> (i * 4)) % chars.length];
    return code;
  }

  Future<SyncPreviewData> fetchSyncPreview(String code) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Harus login terlebih dahulu.");

    String formattedCode = code.trim().toUpperCase();
    if (!formattedCode.startsWith('DYL-')) formattedCode = 'DYL-$formattedCode';

    final query = await _firestore
        .collection('users')
        .where('pairingCode', isEqualTo: formattedCode)
        .where('accountType', isEqualTo: 'managed')
        .limit(1)
        .get();

    if (query.docs.isEmpty)
      throw Exception("Kode tidak ditemukan atau sudah digunakan.");

    final managedDoc  = query.docs.first;
    final managedUid  = managedDoc.id;
    final managedData = managedDoc.data();

    final syncPending = managedData['isSyncPending'];
    if (syncPending != null && syncPending == false) {
      throw Exception("Kode ini sudah pernah digunakan untuk sinkronisasi.");
    }

    try {
      await _firestore
          .collection('users')
          .doc(managedUid)
          .update({'isSyncPending': true});
    } catch (e) {
      debugPrint("Gagal set isSyncPending (non-fatal): $e");
    }

    final currentDoc  = await _firestore.collection('users').doc(user.uid).get();
    final currentData = currentDoc.data() ?? {};

    int totalBooks = 0;
    try {
      final librarySnap = await _firestore
          .collection('users')
          .doc(managedUid)
          .collection('my_library')
          .get();
      totalBooks = librarySnap.docs.length;
    } catch (e) {
      debugPrint("Gagal baca library preview (non-fatal): $e");
    }

    return SyncPreviewData(
      managedUid:           managedUid,
      pairingCode:          formattedCode,
      managedName:          managedData['displayName']?.toString()  ?? '',
      managedAge:           (managedData['age'] is num) ? (managedData['age'] as num).toInt() : 0,
      managedGender:        managedData['gender']?.toString()       ?? '',
      managedGrade:         managedData['grade']?.toString()        ?? '',
      managedDyslexiaType:  managedData['dyslexiaType']?.toString() ?? '',
      managedLinkedTeacher: List<String>.from(managedData['linkedTeacher'] ?? []),
      currentName:          currentData['displayName']?.toString()  ?? '',
      currentAge:           (currentData['age'] is num) ? (currentData['age'] as num).toInt() : 0,
      currentGender:        currentData['gender']?.toString()       ?? '',
      currentGrade:         currentData['grade']?.toString()        ?? '',
      currentDyslexiaType:  currentData['dyslexiaType']?.toString() ?? '',
      totalBooks:           totalBooks,
    );
  }

  Future<void> executeSyncStudent({
    required SyncPreviewData preview,
    required bool            useTeacherProfile,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Harus login terlebih dahulu.");

    final currentRef = _firestore.collection('users').doc(user.uid);
    final managedRef = _firestore.collection('users').doc(preview.managedUid);

    try {
      final libraryDocs = await managedRef.collection('my_library').get();
      WriteBatch batch  = _firestore.batch();
      int       opCount = 0;

      for (final libDoc in libraryDocs.docs) {
        final newBookRef = currentRef.collection('my_library').doc(libDoc.id);

        // FIX: DocumentSnapshot.data() bisa return null jika dokumen dihapus
        // saat proses sync berjalan (race condition). Cast keras tanpa guard → crash.
        final libData = libDoc.data();
        batch.set(newBookRef, libData);
        opCount++;

        for (final lat
            in (await libDoc.reference.collection('latihan').get()).docs) {
          final latData = lat.data();
          batch.set(
              newBookRef.collection('latihan').doc(lat.id), latData);
          opCount++;
          if (opCount >= 400) {
            await batch.commit();
            batch    = _firestore.batch();
            opCount  = 0;
          }
        }

        for (final rek
            in (await libDoc.reference.collection('rekap_latihan').get()).docs) {
          final rekData = rek.data();
          batch.set(
              newBookRef.collection('rekap_latihan').doc(rek.id), rekData);
          opCount++;
          if (opCount >= 400) {
            await batch.commit();
            batch    = _firestore.batch();
            opCount  = 0;
          }
        }
      }
      if (opCount > 0) await batch.commit();
    } catch (e) {
      debugPrint("Sync error migrasi: $e");
      throw Exception(
          "Gagal menyalin data latihan. Cek koneksi dan coba lagi.\n\nDetail: $e");
    }

    try {
      final Map<String, dynamic> profileUpdate = {
        'isProfileComplete': true,
        'accountType':       'independent',
        'linkedTeacher':     FieldValue.arrayUnion(preview.managedLinkedTeacher),
      };

      if (useTeacherProfile) {
        profileUpdate['displayName']  = preview.managedName;
        profileUpdate['age']          = preview.managedAge;
        profileUpdate['gender']       = preview.managedGender;
        profileUpdate['grade']        = preview.managedGrade;
        profileUpdate['dyslexiaType'] = preview.managedDyslexiaType;
      }

      await currentRef.set(profileUpdate, SetOptions(merge: true));

      if (useTeacherProfile && preview.managedName.isNotEmpty) {
        await user.updateDisplayName(preview.managedName);
        await user.reload();
      }
    } catch (e) {
      throw Exception(
          "Data latihan disalin, tapi gagal update profil. Coba lagi.");
    }

    try {
      await managedRef
          .update({'linkedTeacher': [], 'isSyncPending': false});
      await managedRef.delete();
    } catch (e) {
      debugPrint("Gagal hapus akun managed: $e");
    }
  }

  Exception _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':       return Exception("Email tidak terdaftar.");
      case 'wrong-password':       return Exception("Password salah.");
      case 'email-already-in-use': return Exception("Email sudah dipakai.");
      case 'invalid-email':        return Exception("Format email salah.");
      case 'weak-password':        return Exception("Password terlalu lemah.");
      default:                     return Exception(e.message ?? "Terjadi kesalahan.");
    }
  }
}