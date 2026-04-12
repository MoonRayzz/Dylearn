// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/utils/responsive_helper.dart';
import '../../core/models/reading_session.dart';

class FinishDialog extends StatelessWidget {
  final VoidCallback onSurvey;
  final VoidCallback onClose;

  static final TextStyle _base = GoogleFonts.comicNeue(fontWeight: FontWeight.bold);

  const FinishDialog({super.key, required this.onSurvey, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: const Color(0xFFFFFBE6),
      title: Text("Hore, Selesai! 🎉",
          textAlign: TextAlign.center,
          style: _base.copyWith(fontSize: r.font(24), color: Colors.orange.shade800)),
      content: Text(
        "Kamu telah menyelesaikan cerita ini. Hebat sekali!",
        textAlign: TextAlign.center,
        style: TextStyle(
            fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
            fontSize: r.font(15),
            color: Colors.black87),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange, 
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: EdgeInsets.symmetric(horizontal: r.spacing(40), vertical: r.spacing(12))
          ),
          // onSurvey sekarang bertugas memanggil _checkAndRouteToUeq() di read_screen.dart
          onPressed: onSurvey, 
          child: Text("Lanjut", style: _base.copyWith(fontSize: r.font(16))),
        ),
      ],
    );
  }
}

class PracticeSummaryDialog extends StatelessWidget {
  final PracticeSummary summary;
  final VoidCallback onClose;

  static const Color _panelBg = Color(0xFF1A237E);
  static const Color _accent = Color(0xFFFFD54F);
  static const Color _successColor = Color(0xFF66BB6A);
  static const Color _warningColor = Color(0xFFFFA726);

  const PracticeSummaryDialog({super.key, required this.summary, required this.onClose});

  Color _scoreColor(double s) =>
      s >= 80 ? _successColor : (s >= 50 ? _warningColor : Colors.redAccent);
      
  String _scoreEmoji(double s) =>
      s >= 90 ? '🌟' : (s >= 75 ? '🎉' : (s >= 50 ? '👍' : '💪'));

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final avg = summary.avgAccuracy;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
          horizontal: r.spacing(20), vertical: r.spacing(40)),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_panelBg, Color(0xFF283593)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: _panelBg.withOpacity(0.6),
                blurRadius: 30,
                offset: const Offset(0, 8))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(r.spacing(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Rekap Latihan 📋',
                    style: GoogleFonts.comicNeue(
                      fontSize: r.font(20),
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    )),
                SizedBox(height: r.spacing(4)),
                Text(summary.bookTitle,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.comicNeue(
                      fontSize: r.font(12),
                      color: Colors.white54,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                SizedBox(height: r.spacing(20)),

                // Skor rata-rata
                Container(
                  padding: EdgeInsets.all(r.spacing(16)),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: _scoreColor(avg).withOpacity(0.5), width: 1.5),
                  ),
                  child: Column(
                    children: [
                      Text(_scoreEmoji(avg),
                          style: TextStyle(fontSize: r.font(36))),
                      SizedBox(height: r.spacing(4)),
                      Text('${avg.toStringAsFixed(1)}%',
                          style: GoogleFonts.comicNeue(
                            fontSize: r.font(40),
                            fontWeight: FontWeight.w900,
                            color: _scoreColor(avg),
                            height: 1,
                          )),
                      Text('Rata-rata Akurasi',
                          style: GoogleFonts.comicNeue(
                            fontSize: r.font(12),
                            color: Colors.white60,
                            fontWeight: FontWeight.bold,
                          )),
                    ],
                  ),
                ),

                SizedBox(height: r.spacing(16)),

                // 4 stat box
                GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: r.spacing(10),
                  mainAxisSpacing: r.spacing(10),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 2.2,
                  children: [
                    StatBox(
                      label: 'Kalimat Dilatih',
                      value: '${summary.totalSentencesPracticed}/${summary.totalSentencesInBook}',
                      icon: Icons.format_list_numbered_rounded,
                      color: _accent,
                      r: r,
                    ),
                    StatBox(
                      label: 'Total Kata',
                      value: '${summary.totalWordsRead}',
                      icon: Icons.text_fields_rounded,
                      color: Colors.lightBlueAccent,
                      r: r,
                    ),
                    StatBox(
                      label: 'Kata Benar',
                      value: '${summary.totalCorrect}',
                      icon: Icons.check_circle_rounded,
                      color: _successColor,
                      r: r,
                    ),
                    StatBox(
                      label: 'Perlu Latihan',
                      value: '${summary.totalIncorrect + summary.totalMissed}',
                      icon: Icons.warning_rounded,
                      color: Colors.redAccent,
                      r: r,
                    ),
                  ],
                ),

                // Breakdown per kalimat
                if (summary.sentenceBreakdown.isNotEmpty) ...[
                  SizedBox(height: r.spacing(16)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Per Kalimat:',
                        style: GoogleFonts.comicNeue(
                          fontSize: r.font(13),
                          fontWeight: FontWeight.w900,
                          color: Colors.white70,
                        )),
                  ),
                  SizedBox(height: r.spacing(8)),
                  ...summary.sentenceBreakdown.map((s) => Padding(
                        padding: EdgeInsets.only(bottom: r.spacing(6)),
                        child: SentenceRow(sentence: s, r: r),
                      )),
                ],

                // Kata yang sering salah
                if (summary.commonMistakes.isNotEmpty) ...[
                  SizedBox(height: r.spacing(16)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Kata yang Perlu Diperhatikan:',
                        style: GoogleFonts.comicNeue(
                          fontSize: r.font(13),
                          fontWeight: FontWeight.w900,
                          color: Colors.white70,
                        )),
                  ),
                  SizedBox(height: r.spacing(8)),
                  Wrap(
                    spacing: r.spacing(8),
                    runSpacing: r.spacing(6),
                    children: summary.commonMistakes.take(6).map((m) => Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: r.spacing(10),
                            vertical: r.spacing(5),
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.redAccent.withOpacity(0.4)),
                          ),
                          child: Text(
                            '"${m.originalWord}" → "${m.spokenWord}"',
                            style: GoogleFonts.comicNeue(
                              fontSize: r.font(10),
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )).toList(),
                  ),
                ],

                SizedBox(height: r.spacing(20)),

                // Tombol tutup (Akan memicu _checkAndRouteToUeq)
                GestureDetector(
                  onTap: onClose,
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: r.spacing(13)),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text('Keren! Lanjut 🚀',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.comicNeue(
                          fontSize: r.font(15),
                          fontWeight: FontWeight.w900,
                          color: _panelBg,
                        )),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StatBox extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final ResponsiveHelper r;

  const StatBox({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.r,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
            horizontal: r.spacing(10), vertical: r.spacing(8)),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: r.size(20)),
          SizedBox(width: r.spacing(8)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value,
                    style: GoogleFonts.comicNeue(
                      fontSize: r.font(16),
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1,
                    )),
                Text(label,
                    style: GoogleFonts.comicNeue(
                      fontSize: r.font(9),
                      color: Colors.white54,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]),
      );
}

class SentenceRow extends StatelessWidget {
  final SentenceSummary sentence;
  final ResponsiveHelper r;

  static const Color _successColor = Color(0xFF66BB6A);
  static const Color _warningColor = Color(0xFFFFA726);

  const SentenceRow({super.key, required this.sentence, required this.r});

  Color _color(double s) =>
      s >= 80 ? _successColor : (s >= 50 ? _warningColor : Colors.redAccent);

  @override
  Widget build(BuildContext context) {
    final color = _color(sentence.accuracyScore);
    return Row(children: [
      Container(
        width: r.size(28),
        height: r.size(28),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          shape: BoxShape.circle,
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Center(
          child: Text('${sentence.sentenceIndex + 1}',
              style: GoogleFonts.comicNeue(
                fontSize: r.font(10),
                fontWeight: FontWeight.w900,
                color: color,
              )),
        ),
      ),
      SizedBox(width: r.spacing(8)),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sentence.originalText,
                style: GoogleFonts.comicNeue(
                  fontSize: r.font(11),
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            SizedBox(height: r.spacing(3)),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: sentence.accuracyScore / 100,
                minHeight: r.size(4),
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ),
      ),
      SizedBox(width: r.spacing(8)),
      Text('${sentence.accuracyScore.toStringAsFixed(0)}%',
          style: GoogleFonts.comicNeue(
            fontSize: r.font(12),
            fontWeight: FontWeight.w900,
            color: color,
          )),
    ]);
  }
}