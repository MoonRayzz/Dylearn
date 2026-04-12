// ignore_for_file: depend_on_referenced_packages, avoid_print, body_might_complete_normally_catch_error, unnecessary_import, curly_braces_in_flow_control_structures, no_leading_underscores_for_local_identifiers

import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:image/image.dart' as img;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/services/ocr_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/notification_service.dart';

final RegExp _reWhitespace        = RegExp(r'\s+');
final RegExp _reLeadingWhitespace = RegExp(r'^\s+', multiLine: true);
final RegExp _reSentenceSplitter  = RegExp(r'[.!?]+');

class PdfProcessArgs {
  final String pdfPath;
  final List<int> selectedPages;
  final String tempDirPath;
  final RootIsolateToken token;

  PdfProcessArgs({
    required this.pdfPath,
    required this.selectedPages,
    required this.tempDirPath,
    required this.token,
  });
}

class RenderResult {
  final List<String> normalImagePaths;
  final List<String> upscaledImagePaths;
  final String? error;

  RenderResult({
    required this.normalImagePaths,
    required this.upscaledImagePaths,
    this.error,
  });
}

Future<RenderResult> _renderPdfInIsolate(PdfProcessArgs args) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(args.token);
  pdfrx.Pdfrx.getCacheDirectory = () async => args.tempDirPath;

  try {
    final document = await pdfrx.PdfDocument.openFile(args.pdfPath);

    final List<String> normalPaths   = [];
    final List<String> upscaledPaths = [];

    final sortedPages = List<int>.from(args.selectedPages)..sort();

    for (final int pageNumber in sortedPages) {
      if (pageNumber < 0 || pageNumber >= document.pages.length) continue;

      final page    = document.pages[pageNumber];
      final int pageTs = DateTime.now().millisecondsSinceEpoch;

      final normalPdfImage = await page.render(
        width:           page.width.toInt(),
        height:          page.height.toInt(),
        backgroundColor: 0xFFFFFFFF,
      );

      if (normalPdfImage != null) {
        final image = img.Image.fromBytes(
          width:       normalPdfImage.width,
          height:      normalPdfImage.height,
          bytes:       normalPdfImage.pixels.buffer,
          order:       img.ChannelOrder.bgra,
          numChannels: 4,
        );
        normalPdfImage.dispose();
        final jpgBytes  = img.encodeJpg(image, quality: 80);
        final File normalFile =
            File('${args.tempDirPath}/book_normal_${pageTs}_$pageNumber.jpg');
        await normalFile.writeAsBytes(jpgBytes);
        normalPaths.add(normalFile.path);
      }

      final upscaledPdfImage = await page.render(
        width:           (page.width * 2.5).toInt(),
        height:          (page.height * 2.5).toInt(),
        backgroundColor: 0xFFFFFFFF,
      );

      if (upscaledPdfImage != null) {
        final imageUpscaled = img.Image.fromBytes(
          width:       upscaledPdfImage.width,
          height:      upscaledPdfImage.height,
          bytes:       upscaledPdfImage.pixels.buffer,
          order:       img.ChannelOrder.bgra,
          numChannels: 4,
        );
        upscaledPdfImage.dispose();
        final upscaledJpgBytes = img.encodeJpg(imageUpscaled, quality: 95);
        final File upscaledFile = File(
            '${args.tempDirPath}/book_upscaled_${pageTs}_$pageNumber.jpg');
        await upscaledFile.writeAsBytes(upscaledJpgBytes);
        upscaledPaths.add(upscaledFile.path);
      }
    }

    await document.dispose();
    return RenderResult(
      normalImagePaths:   normalPaths,
      upscaledImagePaths: upscaledPaths,
    );
  } catch (e) {
    return RenderResult(
      normalImagePaths:   [],
      upscaledImagePaths: [],
      error:              e.toString(),
    );
  }
}

class UploadProvider with ChangeNotifier {
  final StorageService      _storageService      = StorageService();
  final NotificationService _notificationService = NotificationService();

  bool    _isProcessing          = false;
  bool    _isPublicUploadRunning = false;
  double  _progressValue         = 0.0;
  String  _statusMessage         = '';
  String? _errorMessage;
  bool    _isDisposed            = false;

  bool    get isProcessing          => _isProcessing;
  bool    get isPublicUploadRunning => _isPublicUploadRunning;
  double  get progressValue         => _progressValue;
  String  get statusMessage         => _statusMessage;
  String? get errorMessage          => _errorMessage;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _safeNotify() {
    if (!_isDisposed) notifyListeners();
  }

  void resetState() {
    _isProcessing          = false;
    // FIX: reset flag ini agar getter tidak stuck true setelah proses selesai/error
    _isPublicUploadRunning = false;
    _progressValue         = 0.0;
    _statusMessage         = '';
    _errorMessage          = null;
    _safeNotify();
  }

  void _updateProgress(
    double value,
    String message, {
    bool isFinished = false,
    bool isError    = false,
  }) {
    _progressValue = value;
    _statusMessage = message;
    _safeNotify();

    if (isFinished) {
      _notificationService.stopUploadProgressAndShowResult(
          'Selesai! 🎉', message);
    } else if (isError) {
      _notificationService.stopUploadProgressAndShowResult(
          'Gagal Memproses ❌', message, isError: true);
    } else {
      _notificationService.showUploadProgress(
          (value * 100).toInt(), message);
    }
  }

  Future<void> startBackgroundProcessing({
    required File pdfFile,
    required List<int> selectedPages,
    required Map<String, dynamic> bookMetadata,
    required bool isPublic,
    required String userId,
    File? coverImage,
  }) async {
    // FIX: concurrent guard — tolak panggilan baru jika masih processing
    // tanpa guard, state bisa tertimpa di tengah proses yang sedang berjalan
    if (_isProcessing) return;

    _isProcessing          = true;
    _isPublicUploadRunning = isPublic;
    _errorMessage          = null;

    _updateProgress(0.1, 'Menyiapkan mesin PDF...');

    // FIX: flag untuk melacak apakah OcrService sudah di-dispose
    // agar tidak dipanggil dua kali (sekali di happy path, sekali di catch)
    bool _ocrDisposed = false;

    void disposeOcrOnce() {
      if (!_ocrDisposed) {
        _ocrDisposed = true;
        OcrService.dispose();
      }
    }

    try {
      await WakelockPlus.enable();

      final tempDir = await getTemporaryDirectory();

      _updateProgress(
          0.2, 'Membuka ${selectedPages.length} halaman PDF...');

      final RootIsolateToken? isolateToken = RootIsolateToken.instance;
      if (isolateToken == null) {
        throw Exception(
            'Tidak dapat memulai proses PDF: isolate token tidak tersedia.');
      }

      final isolateArgs = PdfProcessArgs(
        pdfPath:       pdfFile.path,
        selectedPages: selectedPages,
        tempDirPath:   tempDir.path,
        token:         isolateToken,
      );

      final RenderResult renderResult =
          await compute(_renderPdfInIsolate, isolateArgs);

      if (renderResult.error != null ||
          renderResult.normalImagePaths.isEmpty) {
        throw Exception(
            'Gagal mengekstrak halaman PDF: ${renderResult.error}');
      }

      final StringBuffer fullTextBuffer = StringBuffer();
      int totalWordCount = 0;

      for (int i = 0; i < renderResult.upscaledImagePaths.length; i++) {
        final double currentOcrProgress =
            0.3 + ((i / renderResult.upscaledImagePaths.length) * 0.3);
        _updateProgress(
            currentOcrProgress, 'Robot sedang membaca Halaman ${i + 1}...');

        final File upscaledImg =
            File(renderResult.upscaledImagePaths[i]);

        final OcrResult ocrRes =
            await OcrService.convertImageToText(upscaledImg);

        final int passCount = ocrRes.metadata['aiPasses'] as int? ?? 0;
        if (passCount > 0) {
          _updateProgress(currentOcrProgress,
              'Hal ${i + 1} Selesai (AI koreksi $passCount kali)...');
          await Future.delayed(const Duration(milliseconds: 300));
        }

        String pageText = ocrRes.parsedData.fullRawText;
        if (pageText.trim().isEmpty &&
            ocrRes.parsedData.sentences.isNotEmpty) {
          pageText = ocrRes.parsedData.sentences.join(' ');
          debugPrint(
            '[UploadProvider] Hal ${i + 1}: fullRawText kosong, '
            'fallback ke ${ocrRes.parsedData.sentences.length} kalimat.',
          );
        }

        if (pageText.isNotEmpty) {
          if (fullTextBuffer.isNotEmpty) {
            fullTextBuffer.write('\n<PAGE_BREAK>\n');
          }
          fullTextBuffer.write(pageText);
          totalWordCount +=
              _reWhitespace.allMatches(pageText).length + 1;
        }

        try { await upscaledImg.delete(); } catch (_) {}
      }

      disposeOcrOnce();

      final String finalExtractedText = fullTextBuffer
          .toString()
          .replaceAll(_reLeadingWhitespace, '');

      if (finalExtractedText.trim().isEmpty) {
        throw Exception(
            'Cerita tidak terbaca. Pastikan dokumen tidak buram dan teks cukup besar.');
      }

      _updateProgress(0.65, 'Mengunggah Halaman...');

      String? coverUrl;
      if (coverImage != null) {
        final String coverPath =
            isPublic ? 'library_covers/' : 'users/$userId/covers/';
        final String coverName =
            'cover_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final Reference refCover =
            FirebaseStorage.instance.ref().child('$coverPath$coverName');
        await refCover.putFile(coverImage);
        coverUrl = await refCover.getDownloadURL();
      }

      final String pagesPath =
          isPublic ? 'library_pages/' : 'users/$userId/images/';

      _updateProgress(0.70, 'Menyimpan semua halaman ke awan...');

      final List<String?> uploadResults = await Future.wait(
        renderResult.normalImagePaths.map((path) async {
          final File normalImg = File(path);
          try {
            return await _storageService.uploadImage(normalImg, pagesPath);
          } finally {
            try { await normalImg.delete(); } catch (_) {}
          }
        }),
      );

      _updateProgress(0.88, 'Verifikasi halaman...');

      final List<String> uploadedImageUrls =
          uploadResults.whereType<String>().toList();

      if (uploadedImageUrls.isEmpty) {
        throw Exception('Gagal menyimpan halaman ke server.');
      }

      _updateProgress(
        0.9,
        isPublic
            ? 'Menyusun buku di rak perpustakaan...'
            : 'Menyimpan ke perpustakaan pribadi...',
      );

      if (isPublic) {
        final Map<String, dynamic> finalBookData = {
          ...bookMetadata,
          'coverUrl': coverUrl ??
              (uploadedImageUrls.isNotEmpty ? uploadedImageUrls.first : ''),
          'imageUrls':     uploadedImageUrls,
          'imageUrl':      uploadedImageUrls.isNotEmpty
              ? uploadedImageUrls.first
              : (coverUrl ?? ''),
          'content':       finalExtractedText,
          'ocrText':       finalExtractedText,
          'wordCount':     totalWordCount,
          'pageCount':     uploadedImageUrls.length,
          'fileType':      'library_book',
          'status':        'pending',
          'createdAt':     FieldValue.serverTimestamp(),
          'uploadBy':      userId,
          'voteCount':     0,
          'approveCount':  0,
          'requiredVotes': 3,
          'voters':        [],
        };
        await FirebaseFirestore.instance
            .collection('library_books')
            .add(finalBookData);
      } else {
        final int totalSentences =
            finalExtractedText.split(_reSentenceSplitter).length;
        final Map<String, dynamic> privateBookData = {
          ...bookMetadata,
          'timestamp':         FieldValue.serverTimestamp(),
          'fileType':          'pdf',
          'pageCount':         uploadedImageUrls.length,
          'ocrText':           finalExtractedText,
          'ocrConfidence':     100.0,
          'imageUrls':         uploadedImageUrls,
          'imageUrl':          uploadedImageUrls.isNotEmpty
              ? uploadedImageUrls.first
              : '',
          'status':            'Belum Dibaca',
          'durationInSeconds': 0,
          'lastSentenceIndex': 0,
          'totalSentences':    totalSentences,
          'isFinished':        false,
          'lastAccessed':      FieldValue.serverTimestamp(),
        };
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('my_library')
            .add(privateBookData);
      }

      _updateProgress(
        1.0,
        isPublic
            ? 'Selesai! Bukumu masuk antrian Juri Cilik.'
            : 'Buku pribadimu siap dibaca!',
        isFinished: true,
      );

      if (!_isDisposed) {
        await Future.delayed(const Duration(seconds: 2));
        resetState();
      }
    } catch (e) {
      _errorMessage  = 'Gagal: ${e.toString().replaceAll('Exception: ', '')}';
      _statusMessage = 'Ups, proses terhenti.';

      _updateProgress(0.0, _statusMessage, isError: true);
      debugPrint('❌ UploadProvider Error: $e');

      // FIX: panggil disposeOcrOnce() bukan OcrService.dispose() langsung
      // agar tidak double-dispose jika exception terjadi setelah happy path dispose
      disposeOcrOnce();

      if (!_isDisposed) {
        await Future.delayed(const Duration(seconds: 5));
        resetState();
      }
    } finally {
      try { await WakelockPlus.disable(); } catch (_) {}
    }
  }
}