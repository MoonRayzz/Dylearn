// ignore_for_file: avoid_print, curly_braces_in_flow_control_structures

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class ExportService {

  void _writeRow(xlsio.Worksheet sheet, int rowIndex, List<String> rowData,
      {bool isHeader = false}) {
    for (int i = 0; i < rowData.length; i++) {
      final xlsio.Range range = sheet.getRangeByIndex(rowIndex, i + 1);
      range.setText(rowData[i]);
      if (isHeader) {
        range.cellStyle.bold = true;
        range.cellStyle.backColor = '#E0E0E0';
      }
    }
  }

  Future<String> exportAllDataToExcel() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw "Sesi guru tidak valid.";
      final teacherUid = user.uid;

      final firestore = FirebaseFirestore.instance;

      final xlsio.Workbook workbook = xlsio.Workbook();

      final xlsio.Worksheet sheetProfil  = workbook.worksheets[0];
      sheetProfil.name = 'Profil Murid';
      final xlsio.Worksheet sheetBacaan  = workbook.worksheets.addWithName('Mendengarkan & Bacaan');
      final xlsio.Worksheet sheetLatihan = workbook.worksheets.addWithName('Latihan STT (Radar)');
      final xlsio.Worksheet sheetUeq     = workbook.worksheets.addWithName('Hasil UEQ');

      int rowProfil = 1, rowBacaan = 1, rowLatihan = 1, rowUeq = 1;

      _writeRow(sheetProfil, rowProfil++, [
        'UID Murid', 'Nama Lengkap', 'Umur', 'Gender', 'Kelas', 'Tipe Disleksia'
      ], isHeader: true);

      _writeRow(sheetBacaan, rowBacaan++, [
        'UID Murid', 'Nama Murid', 'Judul Buku', 'Total Kalimat',
        'Kalimat Terbaca', 'Progress (%)', 'Durasi Dihabiskan (Detik)'
      ], isHeader: true);

      _writeRow(sheetLatihan, rowLatihan++, [
        'UID Murid', 'Nama Murid', 'Judul Buku', 'Kalimat Dilatih', 'Total Kata',
        'Kata Benar', 'Kurang Tepat', 'Salah/Lewat', 'Akurasi (%)',
        'Ketepatan/Precision (%)', 'Fokus (%)', 'Pengejaan/Spelling (%)',
        'Kelancaran/WPM (%)', 'Kata Sering Salah (Top 5)'
      ], isHeader: true);

      _writeRow(sheetUeq, rowUeq++, [
        'Tanggal', 'UID Murid', 'Nama Murid', 'Judul Buku',
        'Q1', 'Q2', 'Q3', 'Q4', 'Q5', 'Total Skor', 'Kategori'
      ], isHeader: true);

      final studentsQuery = await firestore
          .collection('users')
          .where('linkedTeacher', arrayContains: teacherUid)
          .get();

      if (studentsQuery.docs.isEmpty) {
        workbook.dispose();
        throw "Anda belum memiliki murid untuk diekspor datanya.";
      }

      for (final studentDoc in studentsQuery.docs) {
        final sData = studentDoc.data();
        final String sUid  = studentDoc.id;
        final String sName = sData['displayName']?.toString() ?? 'Tanpa Nama';

        _writeRow(sheetProfil, rowProfil++, [
          sUid,
          sName,
          (sData['age'] ?? '-').toString(),
          (sData['gender'] ?? '-').toString(),
          (sData['grade'] ?? '-').toString(),
          (sData['dyslexiaType'] ?? '-').toString(),
        ]);

        final libraryQuery =
            await studentDoc.reference.collection('my_library').get();

        for (final bookDoc in libraryQuery.docs) {
          final bData          = bookDoc.data();
          final String bTitle  = bData['title']?.toString() ?? 'Tanpa Judul';
          final int totalSentences =
              (bData['totalSentences'] is num)
                  ? (bData['totalSentences'] as num).toInt()
                  : 1;
          final int lastSentence =
              (bData['lastSentenceIndex'] is num)
                  ? (bData['lastSentenceIndex'] as num).toInt()
                  : 0;
          final double progress =
              totalSentences > 0 ? (lastSentence / totalSentences) * 100 : 0;
          final int durationSec =
              (bData['durationInSeconds'] is num)
                  ? (bData['durationInSeconds'] as num).toInt()
                  : 0;

          _writeRow(sheetBacaan, rowBacaan++, [
            sUid, sName, bTitle,
            totalSentences.toString(), lastSentence.toString(),
            progress.toStringAsFixed(1), durationSec.toString(),
          ]);

          final rekapDoc = await bookDoc.reference
              .collection('rekap_latihan')
              .doc('total_rekap')
              .get();

          if (rekapDoc.exists && rekapDoc.data() != null) {
            final rData = rekapDoc.data()!;

            final double accuracy  = (rData['avgAccuracy'] is num) ? (rData['avgAccuracy'] as num).toDouble() : 0.0;
            final int sTrained     = (rData['totalSentencesPracticed'] is num) ? (rData['totalSentencesPracticed'] as num).toInt() : 0;
            final int tWords       = (rData['totalWordsRead'] is num) ? (rData['totalWordsRead'] as num).toInt() : 0;
            final int cWords       = (rData['totalCorrect'] is num) ? (rData['totalCorrect'] as num).toInt() : 0;
            final int pWords       = (rData['totalPartial'] is num) ? (rData['totalPartial'] as num).toInt() : 0;
            final int wWords       = ((rData['totalIncorrect'] is num ? (rData['totalIncorrect'] as num).toInt() : 0) +
                                      (rData['totalMissed'] is num ? (rData['totalMissed'] as num).toInt() : 0));
            final int rDuration    = (rData['totalDurationSeconds'] is num) ? (rData['totalDurationSeconds'] as num).toInt() : 0;

            final double precision = tWords > 0 ? (cWords / tWords) * 100 : 0.0;
            final double focus     = tWords > 0 ? ((tWords - wWords) / tWords) * 100 : 0.0;
            final double spelling  = tWords > 0 ? ((tWords - pWords) / tWords) * 100 : 0.0;

            double fluency = 0.0;
            if (rDuration > 0) {
              final double wpm = tWords / (rDuration / 60.0);
              fluency = (wpm / 50) * 100;
              if (fluency > 100) fluency = 100.0;
            }

            // FIX: safe access — guard null + type check sebelum cast
            String mistakesStr = '-';
            final rawMistakes = rData['commonMistakes'];
            if (rawMistakes is List && rawMistakes.isNotEmpty) {
              final List<String> mList = rawMistakes
                  .take(5)
                  .whereType<Map>()
                  .map((m) {
                    final orig  = m['originalWord']?.toString() ?? '?';
                    final spoke = m['spokenWord']?.toString() ?? '?';
                    final occ   = m['occurrences']?.toString() ?? '0';
                    return '$orig -> $spoke (${occ}x)';
                  })
                  .toList();
              if (mList.isNotEmpty) mistakesStr = mList.join(' | ');
            }

            _writeRow(sheetLatihan, rowLatihan++, [
              sUid, sName, bTitle,
              sTrained.toString(), tWords.toString(),
              cWords.toString(), pWords.toString(), wWords.toString(),
              accuracy.round().toString(), precision.round().toString(),
              focus.round().toString(), spelling.round().toString(),
              fluency.round().toString(), mistakesStr,
            ]);
          }
        }

        // FIX: safe timestamp parsing — guard null + type check
        final ueqQuery = await firestore
            .collection('ueq_results')
            .where('userId', isEqualTo: sUid)
            .get();

        for (final ueqDoc in ueqQuery.docs) {
          final uData = ueqDoc.data();

          String dateStr = '-';
          final ts = uData['timestamp'];
          if (ts is Timestamp) {
            final DateTime date = ts.toDate();
            dateStr = '${date.day}/${date.month}/${date.year}';
          }

          // FIX: safe cast answers — jika bukan Map, pakai empty
          final answersRaw = uData['answers'];
          final Map answers =
              (answersRaw is Map) ? answersRaw : const {};

          final int total = (uData['totalScore'] is num)
              ? (uData['totalScore'] as num).toInt()
              : 0;

          String kategori = 'Netral';
          if (total > 5) kategori = 'Positif (Senang)';
          else if (total < 0) kategori = 'Negatif (Sulit)';

          _writeRow(sheetUeq, rowUeq++, [
            dateStr, sUid, sName,
            uData['docId']?.toString() ?? '-',
            (answers['q1'] ?? 0).toString(),
            (answers['q2'] ?? 0).toString(),
            (answers['q3'] ?? 0).toString(),
            (answers['q4'] ?? 0).toString(),
            (answers['q5'] ?? 0).toString(),
            total.toString(), kategori,
          ]);
        }
      }

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final directory  = await getTemporaryDirectory();
      final String fullPath =
          '${directory.path}/Riset_Dylearn_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final File file = File(fullPath);
      await file.writeAsBytes(bytes);

      return fullPath;
    } catch (e) {
      debugPrint('Export Error: $e');
      throw e.toString();
    }
  }
}