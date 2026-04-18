// ignore_for_file: depend_on_referenced_packages, curly_braces_in_flow_control_structures

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum ImagePreprocessProfile { auto, bookPage, darkPhoto, cleanScan, skip }

class PreprocessResult {
  final File processedFile;
  final File originalFile;
  final ImagePreprocessProfile profileUsed;
  final Map<String, dynamic> diagnostics;
  const PreprocessResult({
    required this.processedFile, required this.originalFile,
    required this.profileUsed,  required this.diagnostics,
  });
}

class OcrImagePreprocessor {

  static Future<PreprocessResult> prepare(File originalFile,
      {ImagePreprocessProfile profile = ImagePreprocessProfile.auto}) async {
    try {
      final Uint8List bytes = await originalFile.readAsBytes();
      final Map<String, dynamic> result =
          await compute(_preprocessIsolate, {'bytes': bytes, 'profile': profile.index});
      final int profileUsedIndex = result['profileUsed'] as int;

      if (profileUsedIndex == ImagePreprocessProfile.skip.index) {
        return PreprocessResult(
          processedFile: originalFile, originalFile: originalFile,
          profileUsed: ImagePreprocessProfile.skip,
          diagnostics: result['diagnostics'] as Map<String, dynamic>,
        );
      }

      final Directory tmpDir = await getTemporaryDirectory();
      final File tempFile = File(p.join(
          tmpDir.path, 'ocr_proc_${DateTime.now().millisecondsSinceEpoch}.png'));
      await tempFile.writeAsBytes(result['processedBytes'] as Uint8List);

      final Map<String, dynamic> diag = result['diagnostics'] as Map<String, dynamic>;
      debugPrint(
        '[Preprocessor] ✓ ${ImagePreprocessProfile.values[profileUsedIndex].name} | '
        'Lum: ${(diag['avgLuminance'] as double?)?.toStringAsFixed(3)} | '
        'EXIF rotated: ${diag['exifRotated']}',
      );

      return PreprocessResult(
        processedFile: tempFile, originalFile: originalFile,
        profileUsed: ImagePreprocessProfile.values[profileUsedIndex],
        diagnostics: diag,
      );
    } catch (e) {
      debugPrint('[Preprocessor] ⚠ Fallback: $e');
      return PreprocessResult(
        processedFile: originalFile, originalFile: originalFile,
        profileUsed: ImagePreprocessProfile.skip,
        diagnostics: {'error': e.toString(), 'fallback': true},
      );
    }
  }

  static Future<void> cleanup(PreprocessResult result) async {
    if (result.processedFile.path == result.originalFile.path) return;
    try {
      if (await result.processedFile.exists()) {
        await result.processedFile.delete();
      }
    } catch (e) {
      debugPrint('[Preprocessor] ⚠ Gagal hapus temp: $e');
    }
  }

  static Map<String, dynamic> _preprocessIsolate(Map<String, dynamic> payload) {
    final Uint8List bytes = payload['bytes'] as Uint8List;
    ImagePreprocessProfile profile =
        ImagePreprocessProfile.values[payload['profile'] as int];

    img.Image? image = img.decodeImage(bytes);
    if (image == null) {
      return {
        'processedBytes': bytes,
        'profileUsed': ImagePreprocessProfile.skip.index,
        'diagnostics': {'error': 'decode_failed', 'exifRotated': false},
      };
    }

    // ── STEP 1: RESIZE & KOREKSI ORIENTASI EXIF [BARU] ─────────────
    // Foto HP sangat besar (up to 12MP). Decode image = 50MB RAM per foto.
    // Resize max 1500px akan memangkas RAM 10x Lipat dan mencegah Out-Of-Memory.
    image = img.bakeOrientation(image);
    final int origW = image.width;
    final int origH = image.height;

    if (image.width > 1500 || image.height > 1500) {
      if (image.width > image.height) {
        image = img.copyResize(image, width: 1500);
      } else {
        image = img.copyResize(image, height: 1500);
      }
    }
    
    final bool wasRotated = (origW != image.width || origH != image.height);
    // ────────────────────────────────────────────────────────────────

    final Map<String, dynamic> analysis = _analyzeImage(image);
    if (profile == ImagePreprocessProfile.auto) {
      profile = _selectProfile(analysis);
    }

    img.Image processed;
    switch (profile) {
      case ImagePreprocessProfile.bookPage:
        processed = _applyBookPageProfile(image);
        break;
      case ImagePreprocessProfile.darkPhoto:
        processed = _applyDarkPhotoProfile(image);
        break;
      case ImagePreprocessProfile.cleanScan:
        processed = _applyCleanScanProfile(image);
        break;
      case ImagePreprocessProfile.skip:
      case ImagePreprocessProfile.auto:
        processed = image;
        // Jika hanya EXIF rotate, pakai cleanScan agar file temp tersimpan
        profile = wasRotated ? ImagePreprocessProfile.cleanScan : ImagePreprocessProfile.skip;
        break;
    }

    return {
      'processedBytes': Uint8List.fromList(img.encodePng(processed)),
      'profileUsed': profile.index,
      'diagnostics': {
        ...analysis,
        'profileApplied': profile.name,
        'exifRotated': wasRotated,   // [BARU] untuk UI feedback
        'outputW': processed.width,
        'outputH': processed.height,
      },
    };
  }

  static Map<String, dynamic> _analyzeImage(img.Image image) {
    final int total = image.width * image.height;
    final int step  = math.max(1, total ~/ 600);
    double sumLum = 0.0, sumCont = 0.0, prevLum = -1.0;
    int count = 0;

    for (int i = 0; i < total; i += step) {
      final int x = i % image.width;
      final int y = i ~/ image.width;
      if (y >= image.height) break;
      final img.Pixel px = image.getPixel(x, y);
      final double lum = (0.299 * px.r + 0.587 * px.g + 0.114 * px.b) / 255.0;
      sumLum += lum;
      if (prevLum >= 0) sumCont += (lum - prevLum).abs();
      prevLum = lum;
      count++;
    }

    if (count == 0) return {'avgLuminance': 0.5, 'avgContrast': 0.1, 'isDark': false, 'isLowContrast': false};
    final double avgLum  = sumLum / count;
    final double avgCont = count > 1 ? sumCont / (count - 1) : 0.1;
    return {
      'avgLuminance': avgLum, 'avgContrast': avgCont,
      'isDark': avgLum < 0.38, 'isLowContrast': avgCont < 0.07,
      'width': image.width, 'height': image.height,
    };
  }

  static ImagePreprocessProfile _selectProfile(Map<String, dynamic> a) {
    if (a['isDark'] as bool) return ImagePreprocessProfile.darkPhoto;
    if (!(a['isLowContrast'] as bool) && (a['avgLuminance'] as double) > 0.70)
      return ImagePreprocessProfile.cleanScan;
    return ImagePreprocessProfile.bookPage;
  }

  // PROFIL 1 — Buku Cetak
  // gaussianBlur(radius:1) [BARU] → noise reduction sebelum binarisasi
  static img.Image _applyBookPageProfile(img.Image src) {
    img.Image out = img.grayscale(src);
    out = img.gaussianBlur(out, radius: 1);   // [BARU]
    out = img.contrast(out, contrast: 130);
    out = _applyOtsuBinarization(out);
    return out;
  }

  // PROFIL 2 — Foto Gelap
  static img.Image _applyDarkPhotoProfile(img.Image src) {
    img.Image out = img.grayscale(src);
    out = img.gaussianBlur(out, radius: 1);   // [BARU]
    out = img.adjustColor(out, gamma: 0.6, brightness: 1.3);
    out = img.contrast(out, contrast: 120);
    out = _applyOtsuBinarization(out);
    return out;
  }

  // PROFIL 3 — Scan Bersih (tidak perlu blur/binarisasi)
  static img.Image _applyCleanScanProfile(img.Image src) {
    img.Image out = img.grayscale(src);
    out = img.contrast(out, contrast: 110);
    return out;
  }

  // OTSU BINARIZATION — manual (adaptiveThreshold tidak ada di image 4.x)
  static img.Image _applyOtsuBinarization(img.Image gray) {
    final List<int> hist = List<int>.filled(256, 0);
    final int total = gray.width * gray.height;
    for (int y = 0; y < gray.height; y++)
      for (int x = 0; x < gray.width; x++)
        hist[gray.getPixel(x, y).r.toInt().clamp(0, 255)]++;

    final int threshold = _otsuThreshold(hist, total);
    final img.Image bin = img.Image(width: gray.width, height: gray.height, numChannels: 1);
    for (int y = 0; y < gray.height; y++)
      for (int x = 0; x < gray.width; x++) {
        final int v = gray.getPixel(x, y).r.toInt().clamp(0, 255) < threshold ? 0 : 255;
        bin.setPixelRgb(x, y, v, v, v);
      }
    return bin;
  }

  static int _otsuThreshold(List<int> hist, int total) {
    if (total == 0) return 128;
    double sumAll = 0;
    for (int i = 0; i < 256; i++) sumAll += i * hist[i];
    double sumBg = 0; int wBg = 0; double maxVar = 0; int best = 128;
    for (int t = 0; t < 256; t++) {
      wBg += hist[t];
      if (wBg == 0) continue;
      final int wFg = total - wBg;
      if (wFg == 0) break;
      sumBg += t * hist[t];
      final double mBg = sumBg / wBg;
      final double mFg = (sumAll - sumBg) / wFg;
      final double d   = mBg - mFg;
      final double v   = wBg.toDouble() * wFg.toDouble() * d * d;
      if (v > maxVar) { maxVar = v; best = t; }
    }
    return best;
  }
}