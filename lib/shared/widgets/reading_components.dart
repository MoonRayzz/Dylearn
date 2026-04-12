// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../providers/settings_provider.dart';
import '../../core/utils/text_utils.dart';
import '../../core/utils/responsive_helper.dart';

// ── PERUBAHAN: evaluationResult DIHAPUS dari InteractiveSentence.
// Feedback warna hijau/merah TIDAK lagi ditampilkan di halaman Mendengarkan.
// Feedback evaluasi sekarang HANYA ditampilkan di dalam PracticeMicPanel
// (mode latihan fullscreen) agar kedua mode benar-benar independen.
typedef NullableTextRange = TextRange?;

class InteractiveSentence extends StatelessWidget {
  final int index;
  final String normalText;
  final String syllableText;
  final bool isActive;
  final ValueNotifier<NullableTextRange>? highlightNotifier;

  // ── evaluationResult DIHAPUS intentional ──────────────────────────────────
  // Tidak ada lagi parameter evaluationResult di sini.
  // Pewarnaan hasil latihan HANYA ada di PracticeMicPanel._buildEvaluatedText()

  final SettingsProvider settings;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ResponsiveHelper r;

  // Warna suku kata — ungu & teal, kontras tinggi di background krem/putih.
  // Keduanya terbukti membantu keterbacaan pada anak disleksia (distinct hue,
  // tidak confusing dengan warna evaluasi hijau/kuning/merah).
  static const Color _syllableColorA = Color(0xFF7B1FA2); // ungu
  static const Color _syllableColorB = Color(0xFF00838F); // teal
  static final Color _activeBgColor = Colors.orange.withOpacity(0.15);
  static final Border _activeBorder =
      Border.all(color: Colors.orange, width: 2.0);
  static final Border _inactiveBorder = Border.all(color: Colors.transparent);
  static final BorderRadius _borderRadius = BorderRadius.circular(16);
  static final TextStyle _highlightStyle = TextStyle(
      backgroundColor: Colors.orange.shade400, color: Colors.white);

  const InteractiveSentence({
    super.key,
    required this.index,
    required this.normalText,
    required this.syllableText,
    required this.isActive,
    required this.settings,
    required this.onTap,
    required this.onLongPress,
    required this.r,
    this.highlightNotifier,
    // evaluationResult SENGAJA tidak ada di sini
  });

  Widget _buildHighlightedRichText(
      String text, TextRange? range, TextStyle style) {
    if (range == null ||
        range.start < 0 ||
        range.end > text.length ||
        range.isCollapsed) {
      return Text(text, textAlign: TextAlign.left, style: style);
    }
    try {
      return RichText(
        textAlign: TextAlign.left,
        text: TextSpan(style: style, children: [
          TextSpan(text: text.substring(0, range.start)),
          TextSpan(
              text: text.substring(range.start, range.end),
              style: _highlightStyle),
          TextSpan(text: text.substring(range.end)),
        ]),
      );
    } catch (e) {
      return Text(text, textAlign: TextAlign.left, style: style);
    }
  }

  Widget _buildColoredSyllableText(
      String text, TextRange? ttsRange, TextStyle baseStyle) {
    final segments = TextUtils.tokenizeWords(text);
    int charOffset = 0;
    final List<InlineSpan> spans = [];

    for (final segment in segments) {
      final segStart = charOffset;
      final segEnd = charOffset + segment.raw.length;
      final isTtsActive = ttsRange != null &&
          segment.isWord &&
          _rangesOverlap(ttsRange, segStart, segEnd);

      if (!segment.isWord || segment.syllables.isEmpty) {
        spans.add(TextSpan(text: segment.raw, style: baseStyle));
      } else if (isTtsActive) {
        // FIX: WidgetSpan + Padding(bottom:4) sebagai jarak antara teks dan garis bawah
        // TextDecoration.underline tidak support offset, sehingga garis menempel teks
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.orange, width: 3),
                ),
              ),
              child: RichText(
                text: TextSpan(
                  children: segment.syllables
                      .map((syl) => TextSpan(
                            text: syl.text,
                            style: baseStyle.copyWith(
                              color: syl.isEven
                                  ? _syllableColorA
                                  : _syllableColorB,
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
        ));
      } else {
        for (final syl in segment.syllables) {
          spans.add(TextSpan(
            text: syl.text,
            style: baseStyle.copyWith(
                color: syl.isEven ? _syllableColorA : _syllableColorB),
          ));
        }
      }
      charOffset = segEnd;
    }
    return RichText(
        textAlign: TextAlign.left,
        text: TextSpan(style: baseStyle, children: spans));
  }

  bool _rangesOverlap(TextRange r, int start, int end) =>
      r.start < end && r.end > start;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      height: settings.lineHeight,
      fontFamily: settings.fontFamily,
      fontSize: r.font(20) * settings.textScaleFactor,
      letterSpacing: settings.letterSpacing,
      color: const Color(0xFF2D3436),
      fontWeight: FontWeight.w500,
    );

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: EdgeInsets.only(bottom: r.spacing(24)),
        padding: EdgeInsets.symmetric(
            horizontal: r.spacing(16), vertical: r.spacing(12)),
        decoration: BoxDecoration(
          color: isActive ? _activeBgColor : Colors.transparent,
          borderRadius: _borderRadius,
          border: isActive ? _activeBorder : _inactiveBorder,
        ),
        // ── Selalu render teks normal / suku kata saja ──────────────────
        // Tidak ada lagi _buildEvaluatedText di sini.
        // Halaman Mendengarkan BERSIH dari warna evaluasi.
        child: isActive && highlightNotifier != null
            ? SentenceHighlightWrapper(
                highlightNotifier: highlightNotifier!,
                normalText: normalText,
                baseStyle: baseStyle,
                isSyllableMode: settings.enableSyllable,
                buildNormal: _buildHighlightedRichText,
                buildSyllable: _buildColoredSyllableText,
              )
            : settings.enableSyllable
                ? _buildColoredSyllableText(normalText, null, baseStyle)
                : Text(normalText, textAlign: TextAlign.left, style: baseStyle),
      ),
    );
  }
}

class SentenceHighlightWrapper extends StatelessWidget {
  final ValueNotifier<NullableTextRange> highlightNotifier;
  final String normalText;
  final TextStyle baseStyle;
  final bool isSyllableMode;
  final Widget Function(String, TextRange?, TextStyle) buildNormal;
  final Widget Function(String, TextRange?, TextStyle) buildSyllable;

  const SentenceHighlightWrapper({
    super.key,
    required this.highlightNotifier,
    required this.normalText,
    required this.baseStyle,
    required this.isSyllableMode,
    required this.buildNormal,
    required this.buildSyllable,
  });

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<NullableTextRange>(
        valueListenable: highlightNotifier,
        builder: (context, range, _) => isSyllableMode
            ? buildSyllable(normalText, range, baseStyle)
            : buildNormal(normalText, range, baseStyle),
      );
}