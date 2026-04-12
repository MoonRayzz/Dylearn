// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // OPTIMASI: Gunakan const Map agar tidak mengalokasikan object baru di memori tiap kali upload
  static const Map<String, String> _defaultCustomMetadata = {'picked-by': 'Dylearn-App'};

  // =======================================================================
  // 1. UPLOAD IMAGE (DENGAN FOLDER PATH DINAMIS)
  // =======================================================================
  Future<String?> uploadImage(File file, String folderPath) async {
    return _uploadFile(
      file: file,
      path: folderPath.endsWith('/') ? folderPath : '$folderPath/',
      contentType: 'image/jpeg',
    );
  }

  // =======================================================================
  // 2. UPLOAD PDF
  // =======================================================================
  Future<String?> uploadPdf(File file, String folderPath) async {
    return _uploadFile(
      file: file,
      path: folderPath.endsWith('/') ? folderPath : '$folderPath/',
      contentType: 'application/pdf',
    );
  }

  // =======================================================================
  // 3. PRIVATE CORE UPLOAD FUNCTION (DRY PATTERN)
  // =======================================================================
  Future<String?> _uploadFile({
    required File file,
    required String path,
    required String contentType,
  }) async {
    try {
      // OPTIMASI: Cukup gunakan basename, tidak perlu memecah extension dan nama file
      // lalu menggabungkannya lagi. Hasil string-nya sama, komputasi CPU lebih ringan.
      final String fileName = "${DateTime.now().millisecondsSinceEpoch}_${p.basename(file.path)}";
      final Reference ref = _storage.ref().child('$path$fileName');

      final metadata = SettableMetadata(
        contentType: contentType,
        customMetadata: _defaultCustomMetadata,
      );

      // OPTIMASI: Langsung await task untuk menghindari pembuatan variabel lokal berlebih
      final TaskSnapshot snapshot = await ref.putFile(file, metadata);
      return await snapshot.ref.getDownloadURL();

    } catch (e) {
      debugPrint("❌ Firebase Storage Error: $e");
      return null;
    }
  }

  // =======================================================================
  // 4. DELETE FILE
  // =======================================================================
  Future<void> deleteFileFromUrl(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } catch (e) {
      debugPrint("❌ Gagal menghapus file: $e");
    }
  }
}