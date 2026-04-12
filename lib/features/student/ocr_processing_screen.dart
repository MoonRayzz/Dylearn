// ignore_for_file: use_build_context_synchronously, unused_field, unused_element_parameter, unnecessary_underscores

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/ocr_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/utils/responsive_helper.dart';
import '../read_screen.dart';
import 'camera_picker_screen.dart';

class OcrProcessingScreen extends StatefulWidget {
  final List<File> imageFiles;
  final String sourceType;
  final String? activeStudentUid;
  final String? activeStudentName;

  const OcrProcessingScreen({
    super.key,
    required this.imageFiles,
    required this.sourceType,
    this.activeStudentUid,
    this.activeStudentName,
  });

  @override
  State<OcrProcessingScreen> createState() => _OcrProcessingScreenState();
}

class _OcrProcessingScreenState extends State<OcrProcessingScreen> {
  final AuthService _authService = AuthService();
  final StorageService _storageService = StorageService();

  final ValueNotifier<String> _statusMessageNotifier =
      ValueNotifier('Menganalisis kualitas teks...');
  final ValueNotifier<double> _progressValueNotifier = ValueNotifier(0.0);
  bool _isProcessing = true;

  static const BorderRadius _dialogRadius = BorderRadius.all(Radius.circular(20));
  static const BorderRadius _buttonRadius = BorderRadius.all(Radius.circular(10));
  static const BorderRadius _progressClipRadius = BorderRadius.all(Radius.circular(4));

  static final ButtonStyle _successButtonStyle = ElevatedButton.styleFrom(
    foregroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: _buttonRadius),
  );
  static final ButtonStyle _errorButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.red,
    foregroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: _buttonRadius),
  );
  static final ButtonStyle _retryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.orange,
    foregroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: _buttonRadius),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _processBatchImages();
    });
  }

  @override
  void dispose() {
    _statusMessageNotifier.dispose();
    _progressValueNotifier.dispose();
    super.dispose();
  }

  void _updateProgress(double value, String message) {
    _progressValueNotifier.value = value;
    _statusMessageNotifier.value = message;
  }

  // ── Dialog rename buku — dipanggil SEBELUM loading spinner ─────────────────
  // Font: ComicNeue (student-side theme)
  Future<String?> _showBookTitleDialog(String suggestedTitle) async {
    final ctrl = TextEditingController(text: suggestedTitle);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        title: Row(
          children: [
            Icon(Icons.drive_file_rename_outline_rounded,
                color: Colors.orange.shade700, size: 22),
            const SizedBox(width: 10),
            Text(
              'Beri Nama Cerita',
              style: GoogleFonts.comicNeue(
                  fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kasih nama yang bagus biar ceritanya mudah ditemukan ya! 📖',
              style: GoogleFonts.comicNeue(
                  fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: GoogleFonts.comicNeue(
                  fontSize: 15, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'Contoh: Kisah Sang Kancil',
                hintStyle: GoogleFonts.comicNeue(
                    color: Colors.grey.shade400, fontSize: 14),
                filled: true,
                fillColor: Colors.orange.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: Colors.orange.shade400, width: 2),
                ),
                prefixIcon:
                    Icon(Icons.auto_stories_rounded, color: Colors.orange.shade400),
                suffixIcon: IconButton(
                  icon:
                      const Icon(Icons.clear_rounded, size: 18, color: Colors.grey),
                  onPressed: () => ctrl.clear(),
                ),
              ),
              onSubmitted: (_) {
                final val = ctrl.text.trim();
                Navigator.pop(ctx, val.isEmpty ? suggestedTitle : val);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, suggestedTitle),
            child: Text('Lewati',
                style: GoogleFonts.comicNeue(
                    color: Colors.grey.shade500, fontSize: 14)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade600,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () {
              final val = ctrl.text.trim();
              Navigator.pop(ctx, val.isEmpty ? suggestedTitle : val);
            },
            child: Text('Simpan Nama',
                style: GoogleFonts.comicNeue(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.white)),
          ),
        ],
      ),
    ).then((result) {
      ctrl.dispose();
      return result;
    });
  }
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _processBatchImages() async {
    _updateProgress(0.0, 'Menganalisis kualitas teks...');

    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception('User tidak login.');

      final StringBuffer combinedText = StringBuffer();
      double totalConfidence = 0.0;
      int processedCount = 0;

      final List<String> uploadedImageUrls = [];
      final int totalFiles = widget.imageFiles.length;

      for (int i = 0; i < totalFiles; i++) {
        if (!mounted) return;

        _updateProgress(
          i / totalFiles,
          'Memproses halaman ${i + 1} dari $totalFiles...',
        );

        final File image = widget.imageFiles[i];

        final Future<String?> uploadFuture =
            _storageService.uploadImage(image, user.uid);
        final Future<OcrResult> ocrFuture =
            OcrService.convertImageToText(image);

        final results = await Future.wait([uploadFuture, ocrFuture]);

        if (!mounted) return;

        final String? url = results[0] as String?;
        final OcrResult ocrResult = results[1] as OcrResult;

        if (url != null) uploadedImageUrls.add(url);

        final String pageText = ocrResult.parsedData.fullRawText;

        if (pageText.trim().isNotEmpty) {
          if (combinedText.isNotEmpty) {
            combinedText.write('\n<PAGE_BREAK>\n');
          }
          combinedText.write(pageText);
          totalConfidence += ocrResult.averageConfidence;
          processedCount++;
        }
      }

      final double finalAverageConfidence =
          processedCount > 0 ? (totalConfidence / processedCount) : 0.0;
      final int confidencePercent = (finalAverageConfidence * 100).toInt();
      final String finalFullText = combinedText.toString().trim();

      if (finalFullText.isEmpty) {
        throw Exception(
            'Tidak ada teks yang terbaca. Pastikan foto jelas dan berisi tulisan.');
      }

      if (mounted) {
        setState(() {
          _progressValueNotifier.value = 1.0;
          _isProcessing = false;
        });

        _showResultDialog(
          score: confidencePercent,
          fullText: finalFullText,
          rawConfidence: finalAverageConfidence,
          userId: user.uid,
          imageUrls: uploadedImageUrls,
        );
      }
    } catch (e) {
      debugPrint('Processing Error: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        _showErrorDialog(
            'Terjadi kesalahan: ${e.toString().replaceAll('Exception:', '')}');
      }
    } finally {
      OcrService.dispose();
    }
  }

  void _showResultDialog({
    required int score,
    required String fullText,
    required double rawConfidence,
    required String userId,
    required List<String> imageUrls,
  }) {
    final bool isGoodQuality = score >= 40;
    final r = context.r;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: _dialogRadius),
          title: Text(
            isGoodQuality ? 'Scan Berhasil' : 'Hasil Terlalu Buram',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: r.font(18),
              color: isGoodQuality ? Colors.green[800] : Colors.red[800],
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SpeedLottie(
                path: isGoodQuality
                    ? 'assets/animations/SUCCESSFUL.json'
                    : 'assets/animations/FAILED.json',
                height: r.size(120),
                speedMultiplier: 0.3,
                repeat: false,
              ),
              SizedBox(height: r.spacing(20)),
              Text(
                isGoodQuality
                    ? 'Cerita berhasil diproses dan siap dibaca.'
                    : 'Maaf, tulisan di foto tidak terlihat jelas.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: r.font(16), fontWeight: FontWeight.bold),
              ),
              SizedBox(height: r.spacing(10)),
              Text(
                isGoodQuality
                    ? 'Teks berhasil diekstrak dari ${widget.imageFiles.length} halaman.'
                    : 'Sistem kesulitan membaca cerita. Yuk, coba foto ulang di tempat yang lebih terang dan pastikan gambarnya tidak goyang ya!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: r.font(14)),
              ),
            ],
          ),
          actions: [
            if (isGoodQuality)
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const CameraPickerScreen()));
                },
                child: Text('Scan Ulang',
                    style: TextStyle(color: Colors.grey, fontSize: r.font(14))),
              ),
            ElevatedButton(
              style: isGoodQuality
                  ? _successButtonStyle.copyWith(
                      backgroundColor: WidgetStatePropertyAll(
                          Theme.of(context).primaryColor))
                  : _retryButtonStyle,
              onPressed: () async {
                Navigator.pop(dialogContext);
                if (isGoodQuality) {
                  await _saveAndNavigate(userId, fullText, rawConfidence, imageUrls);
                } else {
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const CameraPickerScreen()));
                }
              },
              child: Text(
                isGoodQuality ? 'Lanjut Baca' : 'Foto Ulang Sekarang',
                style: TextStyle(fontSize: r.font(14)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(String message) {
    final r = context.r;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: _dialogRadius),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SpeedLottie(
              path: 'assets/animations/FAILED.json',
              height: r.size(150),
              speedMultiplier: 0.3,
              repeat: false,
            ),
            SizedBox(height: r.spacing(16)),
            Text('Gagal Memproses',
                style: TextStyle(
                    color: Colors.red[700],
                    fontWeight: FontWeight.bold,
                    fontSize: r.font(18))),
            SizedBox(height: r.spacing(8)),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: r.font(14), color: Colors.black87)),
          ],
        ),
        actions: [
          ElevatedButton(
            style: _errorButtonStyle,
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Tutup', style: TextStyle(fontSize: r.font(14))),
          ),
        ],
      ),
    );
  }

  // ── PATCH: _saveAndNavigate ───────────────────────────────────────────────
  // Perubahan: tanya nama buku dulu SEBELUM menampilkan loading spinner,
  // lalu gunakan nama tersebut saat save ke Firestore.
  // Semua logic Firestore dan Navigator lainnya tidak berubah.
  Future<void> _saveAndNavigate(
    String userId,
    String fullText,
    double confidence,
    List<String> imageUrls,
  ) async {
    if (!mounted) return;

    // ── 1. Siapkan suggestion dari tanggal (sama seperti semula) ──────────
    final DateTime now = DateTime.now();
    final String defaultTitle = 'Cerita Bergambar ${now.day}/${now.month}';

    // ── 2. Tampilkan dialog rename SEBELUM loading spinner ────────────────
    final String? userTitle = await _showBookTitleDialog(defaultTitle);
    if (!mounted) return;

    final String finalTitle =
        (userTitle != null && userTitle.trim().isNotEmpty)
            ? userTitle.trim()
            : defaultTitle;
    // ─────────────────────────────────────────────────────────────────────

    try {
      // ── 3. Baru tampilkan loading spinner ─────────────────────────────
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(color: Colors.orange),
        ),
      );

      final String targetUid = widget.activeStudentUid ?? userId;

      final DocumentReference docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(targetUid)
          .collection('my_library')
          .add({
        'timestamp':         FieldValue.serverTimestamp(),
        'fileType':          'camera',
        'ocrText':           fullText,
        'ocrConfidence':     confidence,
        'pageCount':         widget.imageFiles.length,
        'imageUrls':         imageUrls,
        'imageUrl':          imageUrls.isNotEmpty ? imageUrls.first : '',
        'status':            'Belum Dibaca',
        'durationInSeconds': 0,
        'title':             finalTitle,  // ← pakai judul dari input user
        'isFinished':        false,
        'lastSentenceIndex': 0,
        'totalSentences':    0,
        'lastAccessed':      FieldValue.serverTimestamp(),
        'createdBy':         userId,
      });

      if (mounted) {
        Navigator.pop(context); // tutup loading spinner
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ReadScreen(
              text: fullText,
              documentId: docRef.id,
              imageUrls: imageUrls,
              activeStudentUid: widget.activeStudentUid,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showErrorDialog('Gagal menyimpan cerita: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Memproses Cerita'),
        automaticallyImplyLeading: false,
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(r.spacing(32)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: r.size(250),
                child: const RepaintBoundary(
                  child: _SpeedLottie(
                    path: 'assets/animations/SCANNER_PDF.json',
                    fit: BoxFit.contain,
                    speedMultiplier: 0.8,
                    repeat: true,
                  ),
                ),
              ),
              SizedBox(height: r.spacing(24)),
              ValueListenableBuilder<String>(
                valueListenable: _statusMessageNotifier,
                builder: (_, message, __) => Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: r.font(16), fontWeight: FontWeight.bold),
                ),
              ),
              SizedBox(height: r.spacing(20)),
              ValueListenableBuilder<double>(
                valueListenable: _progressValueNotifier,
                builder: (_, progress, __) => Column(
                  children: [
                    ClipRRect(
                      borderRadius: _progressClipRadius,
                      child: LinearProgressIndicator(
                        value: progress > 0 ? progress : null,
                        minHeight: r.size(8),
                        color: Colors.orange,
                        backgroundColor: Colors.orange.shade100,
                      ),
                    ),
                    SizedBox(height: r.spacing(10)),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.bold,
                          fontSize: r.font(14)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _SpeedLottie — tidak berubah ──────────────────────────────────────────────

class _SpeedLottie extends StatefulWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool repeat;
  final double speedMultiplier;

  const _SpeedLottie({
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.repeat = true,
    this.speedMultiplier = 1.0,
  });

  @override
  State<_SpeedLottie> createState() => _SpeedLottieState();
}

class _SpeedLottieState extends State<_SpeedLottie>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(
      widget.path,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      controller: _controller,
      frameRate: FrameRate.max,
      onLoaded: (composition) {
        _controller
          ..duration = composition.duration * widget.speedMultiplier
          ..forward();
        if (widget.repeat) _controller.repeat();
      },
      errorBuilder: (_, __, ___) => Icon(
        Icons.error_outline,
        size: (widget.width ?? 100) / 2,
        color: Colors.red,
      ),
    );
  }
}