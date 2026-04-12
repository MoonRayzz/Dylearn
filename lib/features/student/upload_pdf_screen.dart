// ignore_for_file: deprecated_member_use, use_build_context_synchronously, curly_braces_in_flow_control_structures

import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lottie/lottie.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../page_selection_screen.dart';
import '../read_screen.dart';
import '../../shared/widgets/background_wrapper.dart';
import '../../shared/providers/upload_provider.dart';
import '../../core/utils/responsive_helper.dart';

final RegExp _reSentenceSplitter = RegExp(r'[.!?]+');
final DateFormat _historyDateFormat = DateFormat('dd MMM, HH:mm');

class UploadPdfScreen extends StatefulWidget {
  final String? activeStudentUid;
  final String? activeStudentName;

  const UploadPdfScreen({
    super.key,
    this.activeStudentUid,
    this.activeStudentName,
  });

  @override
  State<UploadPdfScreen> createState() => _UploadPdfScreenState();
}

class _UploadPdfScreenState extends State<UploadPdfScreen> {
  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier<bool>(false);
  final User? _user = FirebaseAuth.instance.currentUser;

  Stream<QuerySnapshot>? _pdfStream;

  String get _targetUid => widget.activeStudentUid ?? _user?.uid ?? '';

  @override
  void initState() {
    super.initState();
    if (_targetUid.isNotEmpty) {
      Query query = FirebaseFirestore.instance
          .collection('users')
          .doc(_targetUid)
          .collection('my_library')
          .where('fileType', isEqualTo: 'pdf');

      if (widget.activeStudentUid != null && _user != null) {
        query = query.where('createdBy', isEqualTo: _user.uid);
      }

      _pdfStream = query.orderBy('lastAccessed', descending: true).snapshots();
    }
  }

  @override
  void dispose() {
    _isLoadingNotifier.dispose();
    super.dispose();
  }

  Future<String> _generateFileHash(File file) async {
    try {
      final stream = file.openRead();
      final digest = await sha256.bind(stream).first;
      return digest.toString();
    } catch (e) {
      final stat = await file.stat();
      return '${file.path.split('/').last}_${stat.size}';
    }
  }

  Future<String?> _checkExistingPdf(String fileHash, String fileName) async {
    if (_targetUid.isEmpty) return null;
    try {
      final queryHash = await FirebaseFirestore.instance
          .collection('users')
          .doc(_targetUid)
          .collection('my_library')
          .where('fileType', isEqualTo: 'pdf')
          .where('fileHash', isEqualTo: fileHash)
          .limit(1)
          .get();

      if (queryHash.docs.isNotEmpty) return queryHash.docs.first.id;

      final queryName = await FirebaseFirestore.instance
          .collection('users')
          .doc(_targetUid)
          .collection('my_library')
          .where('fileType', isEqualTo: 'pdf')
          .where('fileName', isEqualTo: fileName)
          .limit(1)
          .get();

      if (queryName.docs.isNotEmpty) return queryName.docs.first.id;
      return null;
    } catch (e) {
      return null;
    }
  }

  // ── Dialog rename buku — dipanggil sebelum proses upload dimulai ─────────
  Future<String?> _showBookTitleDialog(String suggestedTitle) async {
    final ctrl = TextEditingController(text: suggestedTitle);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.drive_file_rename_outline_rounded,
                color: Colors.orange.shade700),
            const SizedBox(width: 10),
            Text(
              'Beri Nama Buku',
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
              'Beri nama yang jelas agar mudah ditemukan nanti.',
              style: GoogleFonts.comicNeue(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: GoogleFonts.comicNeue(
                  fontSize: 15, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'Contoh: Dongeng Kancil',
                hintStyle: GoogleFonts.comicNeue(color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.orange.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: Colors.orange.shade400, width: 2),
                ),
                prefixIcon: Icon(Icons.book_rounded,
                    color: Colors.orange.shade400),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
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
                style: GoogleFonts.comicNeue(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade600,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final val = ctrl.text.trim();
              Navigator.pop(ctx, val.isEmpty ? suggestedTitle : val);
            },
            child: Text('Simpan',
                style: GoogleFonts.comicNeue(
                    fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ],
      ),
    ).then((result) {
      ctrl.dispose();
      return result;
    });
  }

  Future<void> _navigateToPageSelectionAndProcess(
    File pdfFile,
    String fileHash,
    String fileName,
  ) async {
    final List<int>? selectedIndices = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PageSelectionScreen(
          pdfFile: pdfFile,
          fileHash: fileHash,
          isReturningResult: true,
        ),
      ),
    );

    if (selectedIndices != null && selectedIndices.isNotEmpty && mounted) {
      if (_targetUid.isEmpty) return;

      // ── Tanya nama buku sebelum proses dimulai ─────────────────────────
      // Suggestion: nama file tanpa ekstensi, sudah di-clean
      final String suggested = fileName
          .replaceAll('.pdf', '')
          .replaceAll('_', ' ')
          .replaceAll('-', ' ')
          .trim();

      final String? bookTitle = await _showBookTitleDialog(
          suggested.isEmpty ? 'Buku PDF' : suggested);

      if (!mounted) return;

      final String finalTitle =
          (bookTitle != null && bookTitle.trim().isNotEmpty)
              ? bookTitle.trim()
              : suggested.isEmpty
                  ? 'Buku PDF'
                  : suggested;
      // ───────────────────────────────────────────────────────────────────

      final uploadProvider =
          Provider.of<UploadProvider>(context, listen: false);

      final bookMetadata = {
        'fileName': fileName,
        'fileHash': fileHash,
        'title': finalTitle,    // ← pakai judul dari input user
        'createdBy': _user?.uid ?? '',
      };

      uploadProvider.startBackgroundProcessing(
        pdfFile: pdfFile,
        selectedPages: selectedIndices,
        bookMetadata: bookMetadata,
        isPublic: false,
        userId: _targetUid,
        coverImage: null,
      );
    }
  }

  Future<void> _pickPdf() async {
    _isLoadingNotifier.value = true;

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        final File pdfFile = File(result.files.single.path!);
        final String fileName = result.files.single.name;

        final String fileHash = await _generateFileHash(pdfFile);
        final String? existingDocId =
            await _checkExistingPdf(fileHash, fileName);

        if (!mounted) return;

        if (existingDocId != null) {
          _isLoadingNotifier.value = false;

          final bool? userChoice = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              title: const Text('PDF Sudah Ada',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              content:
                  const Text('Ingin melanjutkan baca atau upload ulang?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Upload Ulang',
                      style: TextStyle(color: Colors.orange)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(c, true);
                    _openExistingBook(existingDocId);
                  },
                  child: const Text('Lanjut Baca'),
                ),
              ],
            ),
          );

          if (userChoice == false && mounted) {
            await _deletePdfData(existingDocId);
            await _navigateToPageSelectionAndProcess(
                pdfFile, fileHash, fileName);
          }
        } else {
          await _navigateToPageSelectionAndProcess(pdfFile, fileHash, fileName);
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) _isLoadingNotifier.value = false;
    }
  }

  Future<void> _openExistingBook(String docId) async {
    if (_targetUid.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_targetUid)
          .collection('my_library')
          .doc(docId)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data()!;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReadScreen(
              text: data['ocrText'] ?? '',
              documentId: docId,
              imageUrls: data['imageUrls'] != null
                  ? List<String>.from(data['imageUrls'])
                  : [],
              initialIndex: data['lastSentenceIndex'] ?? 0,
              activeStudentUid: widget.activeStudentUid,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Gagal buka buku: $e');
    }
  }

  Future<void> _deletePdfData(String docId) async {
    if (_targetUid.isEmpty) return;
    try {
      final DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_targetUid)
          .collection('my_library')
          .doc(docId)
          .get();

      if (doc.exists) {
        final Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        final List<Future<dynamic>> deleteTasks = [];

        if (data.containsKey('imageUrls') && data['imageUrls'] is List) {
          final List<String> urls =
              (data['imageUrls'] as List).whereType<String>().toList();
          for (final String url in urls) {
            deleteTasks.add(
              FirebaseStorage.instance
                  .refFromURL(url)
                  .delete()
                  .catchError((_) {}),
            );
          }
        } else if (data['imageUrl'] != null && data['imageUrl'] != '') {
          deleteTasks.add(
            FirebaseStorage.instance
                .refFromURL(data['imageUrl'] as String)
                .delete()
                .catchError((_) {}),
          );
        }

        await Future.wait(deleteTasks);
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('Error hapus: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final isTeacherMode = widget.activeStudentName != null;
    final shortName =
        isTeacherMode ? widget.activeStudentName!.split(' ').first : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isTeacherMode ? 'PDF untuk $shortName' : 'Buku PDF-mu',
          style: GoogleFonts.comicNeue(
            fontWeight: FontWeight.bold,
            fontSize: r.font(isTeacherMode ? 16 : 18),
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: BackgroundWrapper(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  SizedBox(height: kToolbarHeight + r.spacing(30)),
                  PdfUploadAreaWidget(
                    isLoadingNotifier: _isLoadingNotifier,
                    onPickPdf: _pickPdf,
                    r: r,
                  ),
                  SizedBox(height: r.spacing(10)),
                  Consumer<UploadProvider>(
                    builder: (context, provider, child) {
                      if (provider.isProcessing &&
                          !provider.isPublicUploadRunning) {
                        return Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: r.spacing(24),
                            vertical: r.spacing(10),
                          ),
                          child:
                              PdfProgressCardWidget(provider: provider, r: r),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  SizedBox(height: r.spacing(10)),
                ],
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: true,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(30)),
                  child: PdfHistoryListWidget(
                    user: _user,
                    pdfStream: _pdfStream,
                    onDelete: _deletePdfData,
                    r: r,
                    activeStudentUid: widget.activeStudentUid,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Komponen yang tidak berubah — copy langsung dari original ─────────────────

class PdfUploadAreaWidget extends StatelessWidget {
  final ValueNotifier<bool> isLoadingNotifier;
  final VoidCallback onPickPdf;
  final ResponsiveHelper r;

  static final ButtonStyle _uploadButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.orange.shade400,
    foregroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(15)),
    ),
  );

  const PdfUploadAreaWidget({
    super.key,
    required this.isLoadingNotifier,
    required this.onPickPdf,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.spacing(24)),
      child: Column(
        children: [
          SizedBox(
            height: r.size(150),
            child: RepaintBoundary(
              child: Lottie.asset(
                'assets/animations/PDF.json',
                fit: BoxFit.contain,
                frameRate: FrameRate.max,
                errorBuilder: (c, e, s) => Icon(
                  Icons.picture_as_pdf,
                  size: r.size(80),
                  color: Colors.red[300],
                ),
              ),
            ),
          ),
          SizedBox(height: r.spacing(10)),
          ValueListenableBuilder<bool>(
            valueListenable: isLoadingNotifier,
            builder: (context, isLoading, child) {
              return isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton.icon(
                      icon: Icon(Icons.add_rounded, size: r.size(28)),
                      label: const Text('Pilih File Baru'),
                      style: _uploadButtonStyle.copyWith(
                        padding: WidgetStatePropertyAll(
                          EdgeInsets.symmetric(
                            horizontal: r.spacing(40),
                            vertical: r.spacing(12),
                          ),
                        ),
                      ),
                      onPressed: onPickPdf,
                    );
            },
          ),
        ],
      ),
    );
  }
}

class PdfProgressCardWidget extends StatelessWidget {
  final UploadProvider provider;
  final ResponsiveHelper r;

  static final Color _shadowColor = Colors.orange.withOpacity(0.15);
  static const BorderRadius _progressBarRadius =
      BorderRadius.all(Radius.circular(10));
  static const TextStyle _percentLabelStyle = TextStyle(
    fontSize: 12,
    color: Colors.grey,
    fontWeight: FontWeight.bold,
  );

  const PdfProgressCardWidget(
      {super.key, required this.provider, required this.r});

  @override
  Widget build(BuildContext context) {
    final String? bodyFontFamily =
        Theme.of(context).textTheme.bodyMedium?.fontFamily;

    return Container(
      padding: EdgeInsets.all(r.spacing(20)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.all(Radius.circular(24)),
        border: Border.all(color: Colors.orange.shade200, width: 2),
        boxShadow: [
          BoxShadow(color: _shadowColor, blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: r.size(120),
            child: RepaintBoundary(
              child: Lottie.asset(
                'assets/animations/loading_reading.json',
                fit: BoxFit.contain,
                frameRate: FrameRate.max,
              ),
            ),
          ),
          SizedBox(height: r.spacing(16)),
          Text(
            'Sedang Menyiapkan Bukumu...',
            style: GoogleFonts.comicNeue(
              fontWeight: FontWeight.bold,
              fontSize: r.font(18),
              color: Colors.orange.shade800,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: r.spacing(8)),
          Text(
            provider.statusMessage,
            style: TextStyle(
              fontSize: r.font(13),
              color: Colors.grey,
              fontFamily: bodyFontFamily,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: r.spacing(20)),
          Row(
            children: [
              Text('0%', style: _percentLabelStyle.copyWith(fontSize: r.font(12))),
              SizedBox(width: r.spacing(12)),
              Expanded(
                child: ClipRRect(
                  borderRadius: _progressBarRadius,
                  child: LinearProgressIndicator(
                    value: provider.progressValue > 0 ? provider.progressValue : null,
                    backgroundColor: Colors.grey.shade200,
                    color: Colors.orange,
                    minHeight: r.size(12),
                  ),
                ),
              ),
              SizedBox(width: r.spacing(12)),
              Text('100%', style: _percentLabelStyle.copyWith(fontSize: r.font(12))),
            ],
          ),
          SizedBox(height: r.spacing(8)),
          Text(
            '${(provider.progressValue * 100).toInt()}%',
            style: GoogleFonts.comicNeue(
              fontSize: r.font(22),
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade800,
            ),
          ),
          if (provider.errorMessage != null)
            Padding(
              padding: EdgeInsets.only(top: r.spacing(12)),
              child: Text(
                provider.errorMessage!,
                style: TextStyle(color: Colors.red, fontSize: r.font(12)),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class PdfHistoryListWidget extends StatelessWidget {
  final User? user;
  final Stream<QuerySnapshot>? pdfStream;
  final Function(String) onDelete;
  final ResponsiveHelper r;
  final String? activeStudentUid;

  static final TextStyle _comicNueBase = GoogleFonts.comicNeue();

  const PdfHistoryListWidget({
    super.key,
    required this.user,
    required this.pdfStream,
    required this.onDelete,
    required this.r,
    this.activeStudentUid,
  });

  @override
  Widget build(BuildContext context) {
    if (user == null || pdfStream == null) {
      return ListView(physics: const BouncingScrollPhysics(), children: [
        PdfHistoryHeaderWidget(r: r),
        SizedBox(height: r.spacing(80)),
        const Center(child: Text('Silakan login dahulu')),
      ]);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: pdfStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ListView(children: [
            PdfHistoryHeaderWidget(r: r),
            const Center(child: Text('Error memuat data')),
          ]);
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return ListView(children: [
            PdfHistoryHeaderWidget(r: r),
            SizedBox(height: r.spacing(80)),
            const Center(child: CircularProgressIndicator()),
          ]);
        }

        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return ListView(children: [
            PdfHistoryHeaderWidget(r: r),
            SizedBox(height: r.spacing(40)),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.picture_as_pdf_outlined,
                      size: r.size(60), color: Colors.grey[300]),
                  SizedBox(height: r.spacing(16)),
                  Text('Belum ada riwayat PDF.',
                      style: _comicNueBase.copyWith(
                          color: Colors.grey, fontSize: r.font(16))),
                ],
              ),
            ),
          ]);
        }

        final Map<String, QueryDocumentSnapshot> uniquePdfs = {};
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final String fileHash = data['fileHash'] ?? doc.id;
          if (!uniquePdfs.containsKey(fileHash)) uniquePdfs[fileHash] = doc;
        }
        final List<QueryDocumentSnapshot> uniqueDocs =
            uniquePdfs.values.toList();

        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: uniqueDocs.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) return PdfHistoryHeaderWidget(r: r);
            final docIndex = index - 1;
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: r.spacing(16)),
              child: PdfHistoryCardWidget(
                key: ValueKey(uniqueDocs[docIndex].id),
                doc: uniqueDocs[docIndex],
                onDelete: onDelete,
                r: r,
                activeStudentUid: activeStudentUid,
              ),
            );
          },
        );
      },
    );
  }
}

class PdfHistoryHeaderWidget extends StatelessWidget {
  final ResponsiveHelper r;

  static final Color _blueColor = Colors.blue.shade800;
  static final Color _redColor = Colors.red.shade600;

  const PdfHistoryHeaderWidget({super.key, required this.r});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          r.spacing(24), r.spacing(20), r.spacing(24), r.spacing(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Riwayat Bacaan PDF',
              style: GoogleFonts.comicNeue(
                  fontSize: r.font(20),
                  fontWeight: FontWeight.bold,
                  color: _blueColor)),
          Icon(Icons.picture_as_pdf_rounded, color: _redColor),
        ],
      ),
    );
  }
}

class PdfHistoryCardWidget extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Function(String) onDelete;
  final ResponsiveHelper r;
  final String? activeStudentUid;

  static const BorderRadius _cardRadius = BorderRadius.all(Radius.circular(15));
  static const BorderRadius _iconContainerRadius =
      BorderRadius.all(Radius.circular(12));
  static const BorderRadius _progressBarRadius =
      BorderRadius.all(Radius.circular(4));
  static final ButtonStyle _deleteButtonStyle =
      ElevatedButton.styleFrom(backgroundColor: Colors.red);

  const PdfHistoryCardWidget({
    super.key,
    required this.doc,
    required this.onDelete,
    required this.r,
    this.activeStudentUid,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final String docId = doc.id;

    // Tampilkan title jika ada, fallback ke fileName
    final String displayTitle = (data['title'] as String?)?.trim().isNotEmpty == true
        ? data['title']
        : (data['fileName'] ?? 'Tanpa Judul');

    final String ocrText = data['ocrText'] ?? '';
    final List<String> imageUrls = data['imageUrls'] != null
        ? List<String>.from(data['imageUrls'])
        : [];

    final Timestamp? time = data['lastAccessed'];
    final String formattedDate =
        time != null ? _historyDateFormat.format(time.toDate()) : 'Baru saja';

    final int lastIndex = (data['lastSentenceIndex'] ?? 0 as num).toInt();
    int totalSentences = (data['totalSentences'] ?? 0 as num).toInt();

    if (totalSentences == 0 && ocrText.isNotEmpty) {
      totalSentences = ocrText.split(_reSentenceSplitter).length;
    }

    final bool isFinished = data['isFinished'] ?? false;
    double progressValue = 0.0;
    String statusLabel = 'Baru';
    Color statusColor = Colors.orange.shade400;

    if (isFinished) {
      progressValue = 1.0;
      statusLabel = 'Selesai ✅';
      statusColor = Colors.green.shade500;
    } else if (totalSentences > 0) {
      progressValue = (lastIndex / totalSentences).clamp(0.0, 1.0);
      if (progressValue > 0) {
        statusLabel = '${(progressValue * 100).toInt()}%';
        if (progressValue > 0.5) statusColor = Colors.blue.shade500;
      }
    }

    return Card(
      margin: EdgeInsets.only(bottom: r.spacing(12)),
      shape: const RoundedRectangleBorder(borderRadius: _cardRadius),
      elevation: 2,
      child: InkWell(
        borderRadius: _cardRadius,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReadScreen(
                text: ocrText,
                documentId: docId,
                initialIndex: lastIndex,
                imageUrls: imageUrls,
                activeStudentUid: activeStudentUid,
              ),
            ),
          );
        },
        onLongPress: () => _showDeleteDialog(context, displayTitle, docId),
        child: Padding(
          padding: EdgeInsets.all(r.spacing(12)),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(r.spacing(10)),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: _iconContainerRadius,
                ),
                child: Icon(Icons.picture_as_pdf_rounded,
                    color: Colors.redAccent, size: r.size(28)),
              ),
              SizedBox(width: r.spacing(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: r.font(14)),
                    ),
                    SizedBox(height: r.spacing(4)),
                    Text(formattedDate,
                        style: TextStyle(
                            fontSize: r.font(11), color: Colors.grey)),
                    SizedBox(height: r.spacing(8)),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: _progressBarRadius,
                            child: LinearProgressIndicator(
                              value: progressValue,
                              backgroundColor: Colors.grey.shade200,
                              color: statusColor,
                              minHeight: r.size(5),
                            ),
                          ),
                        ),
                        SizedBox(width: r.spacing(8)),
                        Text(statusLabel,
                            style: TextStyle(
                                fontSize: r.font(10),
                                fontWeight: FontWeight.bold,
                                color: statusColor)),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: r.spacing(12)),
              Icon(
                isFinished
                    ? Icons.check_circle_rounded
                    : Icons.arrow_forward_ios_rounded,
                size: isFinished ? r.size(20) : r.size(14),
                color: isFinished ? Colors.green : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, String title, String docId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus PDF?'),
        content: Text("Yakin ingin menghapus '$title'?\n\nSemua data akan hilang."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: _deleteButtonStyle,
            onPressed: () async {
              Navigator.pop(dialogContext);
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);

              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) =>
                    const Center(child: CircularProgressIndicator()),
              );

              try {
                await onDelete(docId);
                navigator.pop();
                messenger.showSnackBar(
                    const SnackBar(content: Text('Berhasil dihapus')));
              } catch (e) {
                navigator.pop();
                messenger.showSnackBar(SnackBar(
                  content: Text(
                      'Gagal menghapus: ${e.toString().replaceAll('Exception:', '')}'),
                  backgroundColor: Colors.red,
                ));
              }
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}