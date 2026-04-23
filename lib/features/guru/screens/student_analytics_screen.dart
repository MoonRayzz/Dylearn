// ignore_for_file: use_build_context_synchronously, curly_braces_in_flow_control_structures, deprecated_member_use, unnecessary_underscores

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

// Package untuk PDF Export
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../config/guru_theme.dart';
import '../../../core/utils/responsive_helper.dart';
import '../components/student_radar_chart.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class DetailedPracticeRecord {
  final String title;
  final double accuracy;
  final int sentencesTrained;
  final int totalWords;
  final int correctWords;
  final int partialWords;
  final int wrongWords;
  final int durationSeconds;
  final List<Map<String, dynamic>> sentences;
  final List<Map<String, String>> mistakes;
  final DateTime? lastPracticed;

  DetailedPracticeRecord({
    required this.title,
    required this.accuracy,
    required this.sentencesTrained,
    required this.totalWords,
    required this.correctWords,
    required this.partialWords,
    required this.wrongWords,
    required this.durationSeconds,
    required this.sentences,
    required this.mistakes,
    required this.lastPracticed,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class StudentAnalyticsScreen extends StatefulWidget {
  final String studentUid;
  final String studentName;

  const StudentAnalyticsScreen({
    super.key,
    required this.studentUid,
    required this.studentName,
  });

  @override
  State<StudentAnalyticsScreen> createState() => _StudentAnalyticsScreenState();
}

class _StudentAnalyticsScreenState extends State<StudentAnalyticsScreen> {
  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier<bool>(true);

  int _totalAssignedTasks = 0;
  int _totalCompletedPractices = 0;
  double _overallAvgAccuracy = 0.0;
  int _totalPracticeMinutes = 0;

  String _studentPhoto = '';
  String _studentGrade = '-';
  String _studentDyslexia = '-';
  int _studentAge = 0;
  String _studentGender = 'L';

  late RadarChartDataModel _radarData;
  List<DetailedPracticeRecord> _practiceHistoryList = [];
  List<Map<String, String>> _globalMistakes = []; // Untuk laporan PDF

  // Key untuk menangkap gambar Radar Chart (RepaintBoundary)
  final GlobalKey _chartKey = GlobalKey();
  bool _isExportingPdf = false;

  @override
  void initState() {
    super.initState();
    _radarData = const RadarChartDataModel(
      accuracy: 0,
      fluency: 0,
      precision: 0,
      focus: 0,
      spelling: 0,
    );
    _fetchAnalyticsData();
  }

  @override
  void dispose() {
    _isLoadingNotifier.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FETCH — MENGAMBIL DATA UNTUK UI & PDF
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _fetchAnalyticsData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Sesi guru tidak valid.");

      final firestore = FirebaseFirestore.instance;

      final studentDoc = await firestore
          .collection('users')
          .doc(widget.studentUid)
          .get();
      if (studentDoc.exists) {
        final sData = studentDoc.data()!;
        _studentPhoto = sData['photoUrl'] ?? '';
        _studentGrade = sData['grade'] ?? '-';
        _studentDyslexia = sData['dyslexiaType'] ?? '-';
        _studentAge = (sData['age'] ?? 0).toInt();
        _studentGender = sData['gender'] ?? 'L';
      }

      final booksQuery = await firestore
          .collection('users')
          .doc(widget.studentUid)
          .collection('my_library')
          .where('createdBy', isEqualTo: user.uid)
          .get();

      _totalAssignedTasks = booksQuery.docs.length;

      double sumAccuracy = 0;
      int countAccuracy = 0;
      int totalSecondsAll = 0;
      int globalTotalWords = 0;
      int globalCorrectWords = 0;
      int globalPartialWords = 0;
      int globalWrongWords = 0;

      List<DetailedPracticeRecord> tempHistory = [];
      Map<String, int> globalMistakeFrequencies = {}; // Simpan semua kesalahan

      for (var bookDoc in booksQuery.docs) {
        final bookData = bookDoc.data();
        final String bookTitle = bookData['title'] ?? 'Tanpa Judul';
        final DateTime? bookDate = (bookData['lastAccessed'] as Timestamp?)
            ?.toDate();

        int bSentencesTrained = 0;
        int bTotalWords = 0;
        int bCorrectWords = 0;
        int bPartialWords = 0;
        int bWrongWords = 0;
        double bAccumulatedAccuracy = 0;
        List<Map<String, dynamic>> bSentenceList = [];
        Map<String, int> mistakeFrequencies = {};

        final latihanQuery = await bookDoc.reference
            .collection('latihan')
            .get();

        if (latihanQuery.docs.isNotEmpty) {
          _totalCompletedPractices++;

          var latDocs = latihanQuery.docs.toList();
          latDocs.sort(
            (a, b) =>
                (int.tryParse(a.id) ?? 0).compareTo(int.tryParse(b.id) ?? 0),
          );

          for (var latDoc in latDocs) {
            final latData = latDoc.data();
            if (latData['evaluationDetails'] != null) {
              bSentencesTrained++;
              final List<dynamic> evals = latData['evaluationDetails'];
              final String originalText = latData['originalText'] ?? '';

              int sTotal = evals.length;
              int sCorrect = 0;
              int sPartial = 0;

              for (var eval in evals) {
                bTotalWords++;
                final String status = eval['status'] ?? 'correct';

                if (status == 'correct') {
                  bCorrectWords++;
                  sCorrect++;
                } else {
                  if (status == 'partially_correct') {
                    bPartialWords++;
                    sPartial++;
                  } else {
                    bWrongWords++;
                  }
                  final String original = (eval['originalWord'] ?? '')
                      .toString();
                  final String spoken = (eval['spokenWord'] ?? '').toString();
                  if (original.isNotEmpty) {
                    final String displaySpoken =
                        (status == 'missed' || spoken.isEmpty)
                        ? '(terlewat)'
                        : spoken;
                    final String mistakeKey = '$original|$displaySpoken';
                    mistakeFrequencies[mistakeKey] =
                        (mistakeFrequencies[mistakeKey] ?? 0) + 1;

                    // Tambahkan ke map global untuk PDF Report
                    globalMistakeFrequencies[mistakeKey] =
                        (globalMistakeFrequencies[mistakeKey] ?? 0) + 1;
                  }
                }
              }

              double sAccuracy = sTotal > 0
                  ? ((sCorrect + (sPartial * 0.5)) / sTotal) * 100
                  : 0.0;
              bAccumulatedAccuracy += sAccuracy;

              bSentenceList.add({
                'text': originalText,
                'score': sAccuracy,
                'evaluations': List<Map<String, dynamic>>.from(
                  evals.map(
                    (e) => {
                      'originalWord': (e['originalWord'] ?? '').toString(),
                      'spokenWord': (e['spokenWord'] ?? '').toString(),
                      'status': (e['status'] ?? 'incorrect').toString(),
                    },
                  ),
                ),
              });
            }
          }

          double bookAvgAccuracy = bSentencesTrained > 0
              ? (bAccumulatedAccuracy / bSentencesTrained)
              : 0.0;

          sumAccuracy += bookAvgAccuracy;
          countAccuracy++;

          globalTotalWords += bTotalWords;
          globalCorrectWords += bCorrectWords;
          globalPartialWords += bPartialWords;
          globalWrongWords += bWrongWords;

          var sortedMistakes = mistakeFrequencies.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          List<Map<String, String>> finalMistakesList = sortedMistakes
              .take(15)
              .map((e) {
                final parts = e.key.split('|');
                return {
                  'original': parts[0],
                  'spoken': parts[1],
                  'count': e.value.toString(),
                };
              })
              .toList();

          int bDuration = 0;
          final rekapDoc = await bookDoc.reference
              .collection('rekap_latihan')
              .doc('total_rekap')
              .get();
          if (rekapDoc.exists) {
            bDuration =
                (rekapDoc.data()!['totalDurationSeconds'] as num?)?.toInt() ??
                0;
          } else {
            bDuration = (bookData['durationInSeconds'] as num?)?.toInt() ?? 0;
          }
          totalSecondsAll += bDuration;

          tempHistory.add(
            DetailedPracticeRecord(
              title: bookTitle,
              accuracy: bookAvgAccuracy,
              sentencesTrained: bSentencesTrained,
              totalWords: bTotalWords,
              correctWords: bCorrectWords,
              partialWords: bPartialWords,
              wrongWords: bWrongWords,
              durationSeconds: bDuration,
              sentences: bSentenceList,
              mistakes: finalMistakesList,
              lastPracticed: bookDate,
            ),
          );
        } else {
          totalSecondsAll +=
              (bookData['durationInSeconds'] as num?)?.toInt() ?? 0;
        }
      }

      // Hitung Radar & Global Mistakes
      if (countAccuracy > 0) {
        _overallAvgAccuracy = sumAccuracy / countAccuracy;
      }
      _totalPracticeMinutes = (totalSecondsAll / 60).round();

      double rPrecision = globalTotalWords > 0
          ? (globalCorrectWords / globalTotalWords) * 100
          : 0.0;
      double rFocus = globalTotalWords > 0
          ? ((globalTotalWords - globalWrongWords) / globalTotalWords) * 100
          : 0.0;
      double rSpelling = globalTotalWords > 0
          ? ((globalTotalWords - globalPartialWords) / globalTotalWords) * 100
          : 0.0;

      double rFluency = 0.0;
      double totalMinutesDec = totalSecondsAll / 60.0;
      if (totalMinutesDec > 0) {
        double wpm = globalTotalWords / totalMinutesDec;
        rFluency = (wpm / 50) * 100;
        if (rFluency > 100) rFluency = 100.0;
      }

      _radarData = RadarChartDataModel(
        accuracy: _overallAvgAccuracy,
        fluency: rFluency,
        precision: rPrecision,
        focus: rFocus,
        spelling: rSpelling,
      );

      // Proses Global Mistakes untuk PDF Report (Ambil 20 kesalahan teratas)
      var sortedGlobalMistakes = globalMistakeFrequencies.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _globalMistakes = sortedGlobalMistakes.take(20).map((e) {
        final parts = e.key.split('|');
        return {
          'original': parts[0],
          'spoken': parts[1],
          'count': e.value.toString(),
        };
      }).toList();

      tempHistory.sort((a, b) {
        if (a.lastPracticed == null && b.lastPracticed == null) return 0;
        if (a.lastPracticed == null) return 1;
        if (b.lastPracticed == null) return -1;
        return b.lastPracticed!.compareTo(a.lastPracticed!);
      });

      _practiceHistoryList = tempHistory;
    } catch (e) {
      debugPrint("Gagal memuat analitik: $e");
    } finally {
      if (mounted) _isLoadingNotifier.value = false;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PDF EXPORT LOGIC
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _exportToPdf() async {
    setState(() => _isExportingPdf = true);

    try {
      final pdf = pw.Document();

      // 1. Ambil Image dari Radar Chart menggunakan RepaintBoundary
      Uint8List? chartImageBytes;
      try {
        if (_chartKey.currentContext != null) {
          final renderObject = _chartKey.currentContext!.findRenderObject();
          if (renderObject is! RenderRepaintBoundary)
            throw Exception('Chart render object bukan RepaintBoundary');
          final RenderRepaintBoundary boundary = renderObject;
          ui.Image image = await boundary.toImage(pixelRatio: 3.0);
          ByteData? byteData = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          chartImageBytes = byteData?.buffer.asUint8List();
        }
      } catch (e) {
        debugPrint("Gagal menangkap gambar chart: $e");
      }

      // 2. Ambil Font untuk mendukung Text rendering di PDF
      final fontRegular = await PdfGoogleFonts.plusJakartaSansRegular();
      final fontBold = await PdfGoogleFonts.plusJakartaSansBold();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
          build: (pw.Context context) {
            return [
              _buildPdfHeader(),
              pw.SizedBox(height: 20),
              _buildPdfProfileCard(),
              pw.SizedBox(height: 20),
              _buildPdfSummarySection(),
              pw.SizedBox(height: 24),

              // Bagian Chart dan Detail Indikator (Menyamping)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (chartImageBytes != null)
                    pw.Expanded(
                      flex: 4,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Grafik Kemampuan',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 10),
                          pw.Center(
                            child: pw.Image(
                              pw.MemoryImage(chartImageBytes),
                              width: 180,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (chartImageBytes != null) pw.SizedBox(width: 16),
                  pw.Expanded(
                    flex: 6,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Detail Indikator Membaca',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 10),
                        _buildPdfIndicatorDetails(),
                      ],
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 24),
              _buildPdfGlobalMistakes(),
              pw.SizedBox(height: 16),
              _buildPdfHistoryTable(),
            ];
          },
        ),
      );

      // Tampilkan interface bawaan OS untuk cetak/simpan PDF
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Rapor_${widget.studentName.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengekspor PDF: $e'),
            backgroundColor: GuruTheme.errorRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }

  // ─── Helper UI untuk PDF ────────────────────────────────────────────────────

  pw.Widget _buildPdfHeader() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'DYLEARN',
              style: pw.TextStyle(
                color: PdfColor.fromHex('#00466C'),
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              'Tanggal Cetak: ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Laporan Detail Perkembangan Membaca Siswa',
          style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 8),
        pw.Divider(color: PdfColor.fromHex('#00466C'), thickness: 2),
      ],
    );
  }

  pw.Widget _buildPdfProfileCard() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Nama Lengkap',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  widget.studentName,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Kelas',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  _studentGrade,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Usia & Gender',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  '${_studentAge > 0 ? '$_studentAge Tahun' : '?'} / $_studentGender',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Tipe Disleksia',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  _studentDyslexia,
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfSummarySection() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        _pdfStatBox('Total Latihan Selesai', '$_totalCompletedPractices Buku'),
        _pdfStatBox(
          'Rata-rata Akurasi',
          '${_overallAvgAccuracy.toStringAsFixed(1)}%',
        ),
        _pdfStatBox('Total Waktu Belajar', '$_totalPracticeMinutes Menit'),
      ],
    );
  }

  pw.Widget _pdfStatBox(String title, String val) {
    return pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            val,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#00466C'),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            title,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfIndicatorDetails() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          _pdfIndicatorRow(
            'Akurasi',
            _radarData.accuracy,
            'Tingkat kecocokan seluruh kata yang diucapkan dengan teks asli.',
          ),
          pw.Divider(color: PdfColors.grey300),
          _pdfIndicatorRow(
            'Ketepatan',
            _radarData.precision,
            'Persentase kata yang diucapkan dengan jelas tanpa terbata.',
          ),
          pw.Divider(color: PdfColors.grey300),
          _pdfIndicatorRow(
            'Kelancaran',
            _radarData.fluency,
            'Kecepatan ritme membaca dan minimnya jeda diam.',
          ),
          pw.Divider(color: PdfColors.grey300),
          _pdfIndicatorRow(
            'Fokus',
            _radarData.focus,
            'Konsentrasi; minimnya pengulangan atau penambahan kata asing.',
          ),
          pw.Divider(color: PdfColors.grey300),
          _pdfIndicatorRow(
            'Pengejaan',
            _radarData.spelling,
            'Ketepatan melafalkan suku kata tanpa ada huruf yang terbalik.',
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfIndicatorRow(String title, double score, String desc) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              title,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              '${score.toStringAsFixed(1)}%',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
                color: PdfColor.fromHex('#00466C'),
              ),
            ),
          ),
          pw.Expanded(
            flex: 6,
            child: pw.Text(
              desc,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.black),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfGlobalMistakes() {
    if (_globalMistakes.isEmpty) return pw.SizedBox();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Kata yang Perlu Diperhatikan (Sering Salah / Terlewat)',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _globalMistakes.map((m) {
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Text(
                '${m['original']} -> ${m['spoken']} (${m['count']}x)',
                style: const pw.TextStyle(fontSize: 9),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  pw.Widget _buildPdfHistoryTable() {
    if (_practiceHistoryList.isEmpty) {
      return pw.Text(
        'Belum ada riwayat latihan yang diselesaikan.',
        style: const pw.TextStyle(color: PdfColors.grey600),
      );
    }

    final headers = [
      'Judul Buku Latihan',
      'Tgl Akses',
      'Akurasi',
      'B / K / S',
      'Waktu',
    ];
    final data = _practiceHistoryList.map((r) {
      final dateStr = r.lastPracticed != null
          ? DateFormat('dd/MM/yy').format(r.lastPracticed!)
          : '-';
      // Benar / Kurang Tepat / Salah
      final bks = '${r.correctWords} / ${r.partialWords} / ${r.wrongWords}';
      final waktu = _formatDuration(r.durationSeconds);
      return [
        r.title,
        dateStr,
        '${r.accuracy.toStringAsFixed(1)}%',
        bks,
        waktu,
      ];
    }).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Detail Riwayat Tugas Membaca',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: data,
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 9,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellAlignments: {
            0: pw.Alignment.centerLeft,
            1: pw.Alignment.center,
            2: pw.Alignment.center,
            3: pw.Alignment.center,
            4: pw.Alignment.center,
          },
          columnWidths: {
            0: const pw.FlexColumnWidth(4),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(2.5),
            4: const pw.FlexColumnWidth(2),
          },
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // INDICATOR INFO SHEET UI
  // ══════════════════════════════════════════════════════════════════════════

  void _showIndicatorInfo(
    BuildContext context,
    ResponsiveHelper r,
    RadarChartDataModel data,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: EdgeInsets.all(r.spacing(24)),
        decoration: const BoxDecoration(
          color: GuruTheme.surfaceLowest,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(r.spacing(10)),
                    decoration: BoxDecoration(
                      color: GuruTheme.primaryFixed,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      color: GuruTheme.primary,
                    ),
                  ),
                  SizedBox(width: r.spacing(16)),
                  Expanded(
                    child: Text(
                      'Panduan Indikator',
                      style: GuruTheme.titleLarge(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: GuruTheme.outline,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              SizedBox(height: r.spacing(20)),
              _buildIndicatorDetail(
                r: r,
                icon: Icons.track_changes_rounded,
                color: GuruTheme.primary,
                title: 'Akurasi',
                score: data.accuracy,
                desc:
                    'Skor rata-rata kecocokan pengucapan dari seluruh sesi latihan (STT). Semakin tinggi, semakin mirip dengan teks bacaan asli.',
              ),
              _divider(),
              _buildIndicatorDetail(
                r: r,
                icon: Icons.check_circle_outline_rounded,
                color: const Color(0xFF0984E3),
                title: 'Ketepatan',
                score: data.precision,
                desc:
                    'Persentase kata yang berhasil diucapkan dengan sempurna tanpa ada kesalahan.\nRumus: (Kata Benar Sempurna / Total Kata) × 100.',
              ),
              _divider(),
              _buildIndicatorDetail(
                r: r,
                icon: Icons.speed_rounded,
                color: GuruTheme.successGreen,
                title: 'Kelancaran',
                score: data.fluency,
                desc:
                    'Mengukur kecepatan dan ketiadaan jeda panjang yang tidak wajar. Skor tinggi menandakan ritme membaca yang konstan dan tidak terbata-bata.',
              ),
              _divider(),
              _buildIndicatorDetail(
                r: r,
                icon: Icons.center_focus_strong_outlined,
                color: GuruTheme.accentOrange,
                title: 'Fokus',
                score: data.focus,
                desc:
                    'Tingkat konsentrasi siswa. Diukur dari minimnya kata yang diulang secara tiba-tiba atau penambahan kata di luar konteks teks.',
              ),
              _divider(),
              _buildIndicatorDetail(
                r: r,
                icon: Icons.spellcheck_rounded,
                color: const Color(0xFF6C5CE7),
                title: 'Pengejaan',
                score: data.spelling,
                desc:
                    'Ketepatan pada level fonem/suku kata. Mendeteksi apakah siswa secara keliru mengeja, membalikkan huruf, atau melompati suku kata tertentu.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    height: 1,
    color: GuruTheme.surfaceHigh,
  );

  Widget _buildIndicatorDetail({
    required ResponsiveHelper r,
    required IconData icon,
    required Color color,
    required String title,
    required double score,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(r.spacing(8)),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: r.size(20), color: color),
        ),
        SizedBox(width: r.spacing(14)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: GuruTheme.titleMedium()),
                  Text(
                    '${score.toStringAsFixed(1)}%',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(desc, style: GuruTheme.bodySmall(), maxLines: 4),
            ],
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final r = context.r;

    return Scaffold(
      backgroundColor: GuruTheme.surfaceLow,
      appBar: _buildAppBar(),
      body: ValueListenableBuilder<bool>(
        valueListenable: _isLoadingNotifier,
        builder: (context, isLoading, _) {
          if (isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: GuruTheme.primary),
            );
          }

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.all(r.spacing(16)),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    // Profile card
                    _buildProfileCard(
                      r,
                    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08),
                    SizedBox(height: r.spacing(20)),

                    if (_totalAssignedTasks == 0) ...[
                      SizedBox(height: r.spacing(40)),
                      _buildEmptyState(r),
                    ] else ...[
                      // Summary cards
                      _buildSummaryCards(
                        r,
                      ).animate(delay: 80.ms).fadeIn(duration: 400.ms),
                      SizedBox(height: r.spacing(24)),

                      // Radar section header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Profil Kemampuan Anak',
                                  style: GuruTheme.titleLarge(),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Peta kekuatan membaca berdasarkan 5 indikator utama.',
                                  style: GuruTheme.bodySmall(),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.info_outline_rounded,
                              size: 22,
                              color: GuruTheme.primary,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () =>
                                _showIndicatorInfo(context, r, _radarData),
                          ),
                        ],
                      ).animate(delay: 160.ms).fadeIn(),
                      SizedBox(height: r.spacing(12)),

                      // Radar chart card — DIBUNGKUS REPAINTBOUNDARY AGAR BISA DICAPTURE KE PDF
                      Container(
                            padding: EdgeInsets.fromLTRB(
                              r.spacing(8),
                              r.spacing(12),
                              r.spacing(8),
                              r.spacing(8),
                            ),
                            decoration: GuruTheme.cardDecoration,
                            child: RepaintBoundary(
                              key: _chartKey,
                              child: StudentRadarChart(data: _radarData, r: r),
                            ),
                          )
                          .animate(delay: 240.ms)
                          .fadeIn(duration: 500.ms)
                          .scale(
                            begin: const Offset(0.95, 0.95),
                            duration: 500.ms,
                          ),

                      SizedBox(height: r.spacing(28)),

                      // History header
                      Row(
                        children: [
                          const Icon(
                            Icons.history_edu_rounded,
                            color: GuruTheme.primary,
                            size: 20,
                          ),
                          SizedBox(width: r.spacing(8)),
                          Text(
                            'Detail Riwayat Latihan',
                            style: GuruTheme.titleLarge(),
                          ),
                        ],
                      ).animate(delay: 320.ms).fadeIn(),
                      SizedBox(height: r.spacing(4)),
                      Text(
                        'Ketuk kartu untuk melihat rincian lengkap evaluasinya.',
                        style: GuruTheme.bodySmall(),
                      ).animate(delay: 320.ms).fadeIn(),
                      SizedBox(height: r.spacing(12)),
                    ],
                  ]),
                ),
              ),

              // History list
              if (_totalAssignedTasks > 0)
                if (_practiceHistoryList.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: r.spacing(16)),
                      child: Container(
                        padding: EdgeInsets.all(r.spacing(20)),
                        decoration: GuruTheme.cardDecoration,
                        child: Center(
                          child: Text(
                            'Anak belum melakukan latihan suara (Speech-to-Text).',
                            style: GuruTheme.bodyMedium(),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ).animate(delay: 400.ms).fadeIn(),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final record = _practiceHistoryList[index];
                      return Padding(
                            padding: EdgeInsets.only(
                              bottom: r.spacing(16),
                              left: r.spacing(16),
                              right: r.spacing(16),
                            ),
                            child: _DetailedHistoryCard(record: record, r: r),
                          )
                          .animate(delay: (320 + (index * 60)).ms)
                          .fadeIn(duration: 400.ms)
                          .slideY(
                            begin: 0.08,
                            duration: 400.ms,
                            curve: Curves.easeOutQuad,
                          );
                    }, childCount: _practiceHistoryList.length),
                  ),

              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).padding.bottom + 64 + 40,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(61),
      child: Container(
        color: GuruTheme.surfaceLowest,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: GuruTheme.primary,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.studentName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GuruTheme.titleMedium(),
                          ),
                          Text(
                            'Laporan Perkembangan',
                            style: GuruTheme.bodySmall(),
                          ),
                        ],
                      ),
                    ),
                    // Tombol Cetak PDF
                    ValueListenableBuilder<bool>(
                      valueListenable: _isLoadingNotifier,
                      builder: (context, isLoading, _) {
                        if (isLoading || _totalCompletedPractices == 0) {
                          return const SizedBox(width: 16);
                        }
                        return Padding(
                          padding: const EdgeInsets.only(right: 16.0),
                          child: _isExportingPdf
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: GuruTheme.primary,
                                  ),
                                )
                              : TextButton.icon(
                                  onPressed: _exportToPdf,
                                  style: TextButton.styleFrom(
                                    backgroundColor: GuruTheme.accentOrange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.print_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    'Cetak PDF',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Container(height: 3, color: GuruTheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(ResponsiveHelper r) {
    return Container(
      padding: EdgeInsets.all(r.spacing(16)),
      decoration: GuruTheme.cardDecoration,
      child: Row(
        children: [
          // Avatar
          Container(
            width: r.size(60),
            height: r.size(60),
            decoration: const BoxDecoration(
              color: GuruTheme.primaryFixed,
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: _studentPhoto.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: _studentPhoto,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: GuruTheme.primary,
                        ),
                      ),
                      errorWidget: (_, __, ___) => Center(
                        child: Text(
                          widget.studentName.isNotEmpty
                              ? widget.studentName[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: r.font(22),
                            fontWeight: FontWeight.w700,
                            color: GuruTheme.primary,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        widget.studentName.isNotEmpty
                            ? widget.studentName[0].toUpperCase()
                            : '?',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: r.font(22),
                          fontWeight: FontWeight.w700,
                          color: GuruTheme.primary,
                        ),
                      ),
                    ),
            ),
          ),
          SizedBox(width: r.spacing(14)),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.studentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GuruTheme.titleLarge(),
                ),
                SizedBox(height: r.spacing(8)),
                Wrap(
                  spacing: r.spacing(6),
                  runSpacing: r.spacing(6),
                  children: [
                    _ProfileBadge(
                      text: _studentGrade,
                      color: GuruTheme.accentOrange,
                      icon: Icons.school_rounded,
                      r: r,
                    ),
                    _ProfileBadge(
                      text:
                          '${_studentAge > 0 ? '$_studentAge Thn' : '?'} • $_studentGender',
                      color: GuruTheme.primary,
                      icon: Icons.person_rounded,
                      r: r,
                    ),
                    _ProfileBadge(
                      text: _studentDyslexia,
                      color: const Color(0xFF6C5CE7),
                      icon: Icons.psychology_rounded,
                      r: r,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(ResponsiveHelper r) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            title: 'Tugas',
            value: _totalAssignedTasks.toString(),
            subtitle: '$_totalCompletedPractices Latihan',
            icon: Icons.menu_book_rounded,
            color: GuruTheme.primary,
            r: r,
          ),
        ),
        SizedBox(width: r.spacing(10)),
        Expanded(
          child: _SummaryCard(
            title: 'Akurasi',
            value: '${_overallAvgAccuracy.toStringAsFixed(1)}%',
            subtitle: 'Rata-rata Total',
            icon: Icons.track_changes_rounded,
            color: GuruTheme.successGreen,
            r: r,
          ),
        ),
        SizedBox(width: r.spacing(10)),
        Expanded(
          child: _SummaryCard(
            title: 'Waktu',
            value: '$_totalPracticeMinutes',
            subtitle: 'Menit (Est)',
            icon: Icons.timer_rounded,
            color: GuruTheme.accentOrange,
            r: r,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ResponsiveHelper r) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
                width: r.size(100),
                height: r.size(100),
                decoration: const BoxDecoration(
                  color: Color(0x0F00466C),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.analytics_outlined,
                  size: r.size(50),
                  color: const Color(0x6600466C),
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: -6, end: 6, duration: 2.seconds),
          SizedBox(height: r.spacing(16)),
          Text(
            'Belum Ada Data Rapor',
            style: GuruTheme.titleLarge(color: const Color(0xFF6B6B80)),
          ).animate().fadeIn(delay: 200.ms),
          SizedBox(height: r.spacing(8)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: r.spacing(32)),
            child: Text(
              'Berikan tugas membaca kepada anak terlebih dahulu. Setelah anak berlatih suara (Mode Mic), rapor akan muncul di sini.',
              textAlign: TextAlign.center,
              style: GuruTheme.bodyMedium(),
            ).animate().fadeIn(delay: 300.ms),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileBadge extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  final ResponsiveHelper r;

  const _ProfileBadge({
    required this.text,
    required this.color,
    required this.icon,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: r.spacing(7),
        vertical: r.spacing(4),
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: r.size(11), color: color),
          SizedBox(width: r.spacing(4)),
          Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: r.font(10),
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final ResponsiveHelper r;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: r.spacing(16),
        horizontal: r.spacing(8),
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: r.size(24)),
          SizedBox(height: r.spacing(8)),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: r.font(20),
              fontWeight: FontWeight.w700,
              color: GuruTheme.onSurface,
              height: 1.1,
            ),
          ),
          SizedBox(height: r.spacing(4)),
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: r.font(12),
              fontWeight: FontWeight.w600,
              color: GuruTheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: r.spacing(2)),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: r.font(9),
              color: GuruTheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DetailedHistoryCard — expandable, dark indigo saat expand untuk data viz
// ─────────────────────────────────────────────────────────────────────────────

class _DetailedHistoryCard extends StatefulWidget {
  final DetailedPracticeRecord record;
  final ResponsiveHelper r;

  const _DetailedHistoryCard({required this.record, required this.r});

  @override
  State<_DetailedHistoryCard> createState() => _DetailedHistoryCardState();
}

class _DetailedHistoryCardState extends State<_DetailedHistoryCard> {
  bool _isExpanded = false;

  // Warna per status kata — konsisten dengan PracticeMicPanel
  static const Color _cCorrect = Color(0xFF30D36E);
  static const Color _cPartial = Color(0xFFF6A22C);
  static const Color _cWrong = Color(0xFFED4C5C);
  static const Color _cMissed = Color(0xFF9E9E9E);

  Color _colorFor(String status) {
    switch (status) {
      case 'correct':
        return _cCorrect;
      case 'partially_correct':
        return _cPartial;
      case 'missed':
        return _cMissed;
      default:
        return _cWrong;
    }
  }

  String _labelFor(String status) {
    switch (status) {
      case 'correct':
        return 'Benar';
      case 'partially_correct':
        return 'Kurang Tepat';
      case 'missed':
        return 'Terlewat';
      default:
        return 'Salah';
    }
  }

  void _showWordDetailSheet({
    required BuildContext context,
    required ResponsiveHelper r,
    required int sentenceIndex,
    required String sentenceText,
    required List<Map<String, dynamic>> evaluations,
    required double score,
  }) {
    final int total = evaluations.length;
    final int correct = evaluations
        .where((e) => e['status'] == 'correct')
        .length;
    final int partial = evaluations
        .where((e) => e['status'] == 'partially_correct')
        .length;
    final int wrong = evaluations
        .where((e) => e['status'] == 'incorrect' || e['status'] == 'missed')
        .length;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: GuruTheme.primaryContainer,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: EdgeInsets.only(
                  top: r.spacing(12),
                  bottom: r.spacing(4),
                ),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  r.spacing(20),
                  r.spacing(8),
                  r.spacing(20),
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: r.spacing(10),
                            vertical: r.spacing(4),
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Kalimat $sentenceIndex',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: r.font(11),
                              fontWeight: FontWeight.w700,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${score.round()}%',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: r.font(18),
                            fontWeight: FontWeight.w700,
                            color: score >= 85
                                ? _cCorrect
                                : score >= 60
                                ? _cPartial
                                : _cWrong,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: r.spacing(10)),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(r.spacing(12)),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '"$sentenceText"',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: r.font(13),
                          color: Colors.white.withOpacity(0.9),
                          fontStyle: FontStyle.italic,
                          height: 1.5,
                        ),
                      ),
                    ),
                    SizedBox(height: r.spacing(12)),
                    Row(
                      children: [
                        _MiniStat(
                          label: 'Benar',
                          value: correct,
                          color: _cCorrect,
                          r: r,
                        ),
                        SizedBox(width: r.spacing(8)),
                        _MiniStat(
                          label: 'Kurang',
                          value: partial,
                          color: _cPartial,
                          r: r,
                        ),
                        SizedBox(width: r.spacing(8)),
                        _MiniStat(
                          label: 'Salah',
                          value: wrong,
                          color: _cWrong,
                          r: r,
                        ),
                        SizedBox(width: r.spacing(8)),
                        _MiniStat(
                          label: 'Total',
                          value: total,
                          color: Colors.white54,
                          r: r,
                        ),
                      ],
                    ),
                    SizedBox(height: r.spacing(12)),
                    Row(
                      children: [
                        _LegendDot(color: _cCorrect, label: 'Benar', r: r),
                        SizedBox(width: r.spacing(12)),
                        _LegendDot(
                          color: _cPartial,
                          label: 'Kurang Tepat',
                          r: r,
                        ),
                        SizedBox(width: r.spacing(12)),
                        _LegendDot(color: _cWrong, label: 'Salah', r: r),
                        SizedBox(width: r.spacing(12)),
                        _LegendDot(color: _cMissed, label: 'Terlewat', r: r),
                      ],
                    ),
                    SizedBox(height: r.spacing(12)),
                    Text(
                      'Evaluasi Per Kata:',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: r.font(13),
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: r.spacing(10)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  padding: EdgeInsets.fromLTRB(
                    r.spacing(20),
                    0,
                    r.spacing(20),
                    r.spacing(32),
                  ),
                  itemCount: evaluations.length,
                  itemBuilder: (_, i) {
                    final e = evaluations[i];
                    final String orig = e['originalWord'] ?? '';
                    final String spoken = e['spokenWord'] ?? '';
                    final String status = e['status'] ?? 'incorrect';
                    final Color wColor = _colorFor(status);
                    final String wLabel = _labelFor(status);
                    final bool isMissed = status == 'missed';
                    final bool isCorrect = status == 'correct';

                    return Container(
                      margin: EdgeInsets.only(bottom: r.spacing(8)),
                      padding: EdgeInsets.symmetric(
                        horizontal: r.spacing(14),
                        vertical: r.spacing(10),
                      ),
                      decoration: BoxDecoration(
                        color: wColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: wColor.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: r.size(22),
                            height: r.size(22),
                            decoration: BoxDecoration(
                              color: wColor.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${i + 1}',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: r.font(9),
                                  fontWeight: FontWeight.w700,
                                  color: wColor,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: r.spacing(12)),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  orig,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: r.font(15),
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                if (!isCorrect) ...[
                                  SizedBox(height: r.spacing(2)),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.mic_rounded,
                                        size: r.size(10),
                                        color: Colors.white38,
                                      ),
                                      SizedBox(width: r.spacing(4)),
                                      Text(
                                        isMissed ? '(tidak diucapkan)' : spoken,
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: r.font(11),
                                          color: Colors.white54,
                                          fontStyle: isMissed
                                              ? FontStyle.italic
                                              : FontStyle.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: r.spacing(8),
                              vertical: r.spacing(4),
                            ),
                            decoration: BoxDecoration(
                              color: wColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              wLabel,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: r.font(9),
                                fontWeight: FontWeight.w700,
                                color: wColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final record = widget.record;

    Color headerAccent = GuruTheme.successGreen;
    if (record.accuracy < 60)
      headerAccent = GuruTheme.errorRed;
    else if (record.accuracy < 85)
      headerAccent = GuruTheme.warningAmber;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: GuruTheme.surfaceLowest,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _isExpanded
                ? headerAccent.withOpacity(0.14)
                : const Color(0x0800466C),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Collapsed header
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(16),
            splashColor: headerAccent.withOpacity(0.05),
            highlightColor: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.all(r.spacing(16)),
              child: Row(
                children: [
                  // Accuracy circle
                  Container(
                    width: r.size(50),
                    height: r.size(50),
                    decoration: BoxDecoration(
                      color: headerAccent.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${record.accuracy.round()}%',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          color: headerAccent,
                          fontSize: r.font(13),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: r.spacing(14)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GuruTheme.titleMedium(),
                        ),
                        SizedBox(height: r.spacing(4)),
                        Text(
                          '${record.sentencesTrained} Kalimat • ${_formatDuration(record.durationSeconds)}',
                          style: GuruTheme.bodySmall(),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: GuruTheme.outlineVariant,
                  ),
                ],
              ),
            ),
          ),

          // Expanded detail (dark background untuk data viz — dipertahankan by design)
          if (_isExpanded)
            Container(
                  padding: EdgeInsets.fromLTRB(
                    r.spacing(16),
                    0,
                    r.spacing(16),
                    r.spacing(16),
                  ),
                  decoration: const BoxDecoration(
                    color: GuruTheme.primaryContainer,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: r.spacing(16)),
                      // Stat boxes 2x3 grid
                      Row(
                        children: [
                          Expanded(
                            child: _StatBox(
                              title: 'Waktu Latihan',
                              value: _formatDuration(record.durationSeconds),
                              icon: Icons.timer_outlined,
                              color: const Color(0xFFA566FF),
                              r: r,
                            ),
                          ),
                          SizedBox(width: r.spacing(8)),
                          Expanded(
                            child: _StatBox(
                              title: 'Total Kalimat',
                              value: '${record.sentencesTrained}',
                              icon: Icons.format_list_numbered_rounded,
                              color: const Color(0xFF38B6FF),
                              r: r,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: r.spacing(8)),
                      Row(
                        children: [
                          Expanded(
                            child: _StatBox(
                              title: 'Total Kata',
                              value: '${record.totalWords}',
                              icon: Icons.text_fields_rounded,
                              color: Colors.blueGrey.shade300,
                              r: r,
                            ),
                          ),
                          SizedBox(width: r.spacing(8)),
                          Expanded(
                            child: _StatBox(
                              title: 'Kata Benar',
                              value: '${record.correctWords}',
                              icon: Icons.check_circle_outline_rounded,
                              color: _cCorrect,
                              r: r,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: r.spacing(8)),
                      Row(
                        children: [
                          Expanded(
                            child: _StatBox(
                              title: 'Kurang Tepat',
                              value: '${record.partialWords}',
                              icon: Icons.spellcheck_rounded,
                              color: _cPartial,
                              r: r,
                            ),
                          ),
                          SizedBox(width: r.spacing(8)),
                          Expanded(
                            child: _StatBox(
                              title: 'Salah / Lewat',
                              value: '${record.wrongWords}',
                              icon: Icons.warning_amber_rounded,
                              color: _cWrong,
                              r: r,
                            ),
                          ),
                        ],
                      ),

                      // Kata sering salah
                      if (record.mistakes.isNotEmpty) ...[
                        SizedBox(height: r.spacing(20)),
                        Text(
                          'Kata yang Perlu Diperhatikan:',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            fontSize: r.font(13),
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: r.spacing(10)),
                        Wrap(
                          spacing: r.spacing(8),
                          runSpacing: r.spacing(8),
                          children: record.mistakes
                              .map(
                                (m) => Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: r.spacing(12),
                                    vertical: r.spacing(7),
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.15),
                                    ),
                                  ),
                                  child: RichText(
                                    text: TextSpan(
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: r.font(11),
                                        color: Colors.white,
                                      ),
                                      children: [
                                        TextSpan(
                                          text: '"${m['original']}"',
                                          style: const TextStyle(
                                            color: Color(0xFFF6A22C),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const TextSpan(text: '  →  '),
                                        TextSpan(
                                          text: '"${m['spoken']}"',
                                          style: const TextStyle(
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                        TextSpan(
                                          text: '  (${m['count']}x)',
                                          style: const TextStyle(
                                            fontSize: 9,
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],

                      // Rincian per kalimat
                      SizedBox(height: r.spacing(20)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Rincian Per Kalimat:',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: r.font(13),
                              color: Colors.white,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.touch_app_rounded,
                                size: r.size(12),
                                color: Colors.white54,
                              ),
                              SizedBox(width: r.spacing(4)),
                              Text(
                                'Ketuk untuk detail',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: r.font(9),
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: r.spacing(12)),

                      ...record.sentences.asMap().entries.map((entry) {
                        final int idx = entry.key + 1;
                        final String text = entry.value['text'];
                        final double score = entry.value['score'];
                        final List<Map<String, dynamic>> evals =
                            List<Map<String, dynamic>>.from(
                              (entry.value['evaluations'] as List? ?? []).map(
                                (e) => Map<String, dynamic>.from(e as Map),
                              ),
                            );

                        Color barColor = _cCorrect;
                        if (score < 60)
                          barColor = _cWrong;
                        else if (score < 85)
                          barColor = _cPartial;

                        return Padding(
                          padding: EdgeInsets.only(bottom: r.spacing(10)),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: evals.isNotEmpty
                                    ? Border.all(
                                        color: barColor.withOpacity(0.25),
                                        width: 1,
                                      )
                                    : null,
                              ),
                              child: InkWell(
                                onTap: evals.isEmpty
                                    ? null
                                    : () => _showWordDetailSheet(
                                        context: context,
                                        r: r,
                                        sentenceIndex: idx,
                                        sentenceText: text,
                                        evaluations: evals,
                                        score: score,
                                      ),
                                borderRadius: BorderRadius.circular(12),
                                splashColor: barColor.withOpacity(0.15),
                                highlightColor: Colors.transparent,
                                child: Padding(
                                  padding: EdgeInsets.all(r.spacing(12)),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: r.size(24),
                                        height: r.size(24),
                                        decoration: BoxDecoration(
                                          color: barColor.withOpacity(0.2),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: barColor.withOpacity(0.6),
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '$idx',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: r.font(10),
                                              fontWeight: FontWeight.w700,
                                              color: barColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: r.spacing(12)),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              text,
                                              style:
                                                  GoogleFonts.plusJakartaSans(
                                                    fontSize: r.font(13),
                                                    color: Colors.white
                                                        .withOpacity(0.9),
                                                  ),
                                            ),
                                            SizedBox(height: r.spacing(8)),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                    child:
                                                        LinearProgressIndicator(
                                                          value: score / 100,
                                                          minHeight: 6,
                                                          backgroundColor:
                                                              Colors.white
                                                                  .withOpacity(
                                                                    0.1,
                                                                  ),
                                                          color: barColor,
                                                        ),
                                                  ),
                                                ),
                                                SizedBox(width: r.spacing(8)),
                                                Text(
                                                  '${score.round()}%',
                                                  style:
                                                      GoogleFonts.plusJakartaSans(
                                                        fontSize: r.font(11),
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: barColor,
                                                      ),
                                                ),
                                              ],
                                            ),
                                            if (evals.isNotEmpty) ...[
                                              SizedBox(height: r.spacing(5)),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.touch_app_rounded,
                                                    size: r.size(10),
                                                    color: Colors.white
                                                        .withOpacity(0.4),
                                                  ),
                                                  SizedBox(width: r.spacing(4)),
                                                  Text(
                                                    'Ketuk untuk lihat detail per kata',
                                                    style:
                                                        GoogleFonts.plusJakartaSans(
                                                          fontSize: r.font(10),
                                                          color: Colors.white
                                                              .withOpacity(0.4),
                                                          fontStyle:
                                                              FontStyle.italic,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                )
                .animate()
                .fadeIn(duration: 280.ms)
                .slideY(begin: -0.04, duration: 280.ms, curve: Curves.easeOut),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat box (di dalam expanded dark panel)
// ─────────────────────────────────────────────────────────────────────────────

class _StatBox extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final ResponsiveHelper r;

  const _StatBox({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.r,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.all(r.spacing(12)),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: r.size(20)),
            Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: r.font(16),
                color: Colors.white,
              ),
            ),
          ],
        ),
        SizedBox(height: r.spacing(8)),
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: r.font(10),
            color: Colors.white70,
          ),
        ),
      ],
    ),
  );
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final ResponsiveHelper r;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
    required this.r,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: EdgeInsets.symmetric(vertical: r.spacing(6)),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: GoogleFonts.plusJakartaSans(
              fontSize: r.font(16),
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: r.font(9),
              color: Colors.white54,
            ),
          ),
        ],
      ),
    ),
  );
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final ResponsiveHelper r;

  const _LegendDot({required this.color, required this.label, required this.r});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: r.size(8),
        height: r.size(8),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      SizedBox(width: r.spacing(4)),
      Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: r.font(9),
          color: Colors.white54,
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Format Duration Helper (di luar class agar bisa diakses global oleh file ini)
// ─────────────────────────────────────────────────────────────────────────────
String _formatDuration(int seconds) {
  if (seconds == 0) return '-';
  if (seconds < 60) return '< 1m';
  final int minutes = seconds ~/ 60;
  final int secs = seconds % 60;
  if (secs == 0) return '${minutes}m';
  return '${minutes}m ${secs}s';
}
