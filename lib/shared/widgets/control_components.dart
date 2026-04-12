import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/utils/responsive_helper.dart';

class CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const CircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color = Colors.black45,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(4.0),
        child: CircleAvatar(
          backgroundColor: color,
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            onPressed: onTap,
          ),
        ),
      );
}

class ReaderControls extends StatelessWidget {
  final bool isPlaying;
  final bool isReady;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ResponsiveHelper r;

  static const BoxDecoration _decoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.all(Radius.circular(40)),
    boxShadow: [
      BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))
    ],
  );

  const ReaderControls({
    super.key,
    required this.isPlaying,
    required this.isReady,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.r,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
            horizontal: r.spacing(16), vertical: r.spacing(8)),
        decoration: _decoration,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.fast_rewind_rounded,
                  color: Colors.orange, size: r.size(28)),
              onPressed: onPrev,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            SizedBox(width: r.spacing(20)),
            GestureDetector(
              onTap: onPlayPause,
              child: CircleAvatar(
                radius: r.size(26),
                backgroundColor: Colors.orange,
                child: isReady
                    ? Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: r.size(32),
                      )
                    : const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
              ),
            ),
            SizedBox(width: r.spacing(20)),
            IconButton(
              icon: Icon(Icons.fast_forward_rounded,
                  color: Colors.orange, size: r.size(28)),
              onPressed: onNext,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      );
}

class ReadingModeTabSwitcher extends StatelessWidget {
  final ValueNotifier<bool> isPracticeMode;
  final int currentPage;
  final int totalPages;
  final VoidCallback onToggle;
  final ResponsiveHelper r;

  static const Color _ttsTabColor = Color(0xFFFF8F00);
  static const Color _practiceTabColor = Color(0xFF1A237E);

  // FIX: pre-compute shadow colors sebagai const
  // _ttsTabColor(0xFFFF8F00) * 0.35 opacity → 0.35*255=89=0x59
  static const Color _ttsShadowColor = Color(0x59FF8F00);
  // _practiceTabColor(0xFF1A237E) * 0.40 opacity → 0.40*255=102=0x66
  static const Color _practiceShadowColor = Color(0x661A237E);

  static const List<BoxShadow> _ttsShadow = [
    BoxShadow(color: _ttsShadowColor, blurRadius: 8, offset: Offset(0, 2))
  ];
  static const List<BoxShadow> _practiceShadow = [
    BoxShadow(
        color: _practiceShadowColor, blurRadius: 8, offset: Offset(0, 2))
  ];

  const ReadingModeTabSwitcher({
    super.key,
    required this.isPracticeMode,
    required this.currentPage,
    required this.totalPages,
    required this.onToggle,
    required this.r,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: isPracticeMode,
        builder: (context, isPractice, _) => Column(
          children: [
            Padding(
              padding: EdgeInsets.only(top: r.spacing(10)),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            SizedBox(height: r.spacing(10)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: r.spacing(20)),
              child: Container(
                height: r.size(44),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EDDF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: isPractice ? onToggle : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOut,
                        margin: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: !isPractice
                              ? _ttsTabColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                          // FIX: gunakan const list — tidak alokasikan BoxShadow baru tiap rebuild
                          boxShadow:
                              !isPractice ? _ttsShadow : const [],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.volume_up_rounded,
                                size: r.size(15),
                                color: !isPractice
                                    ? Colors.white
                                    : Colors.grey[500]),
                            SizedBox(width: r.spacing(5)),
                            Text('Dengarkan',
                                style: GoogleFonts.comicNeue(
                                  fontSize: r.font(12),
                                  fontWeight: FontWeight.w900,
                                  color: !isPractice
                                      ? Colors.white
                                      : Colors.grey[500],
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: !isPractice ? onToggle : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOut,
                        margin: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: isPractice
                              ? _practiceTabColor
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                          // FIX: gunakan const list — tidak alokasikan BoxShadow baru tiap rebuild
                          boxShadow:
                              isPractice ? _practiceShadow : const [],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.mic_rounded,
                                size: r.size(15),
                                color: isPractice
                                    ? Colors.white
                                    : Colors.grey[500]),
                            SizedBox(width: r.spacing(5)),
                            Text('Latihan',
                                style: GoogleFonts.comicNeue(
                                  fontSize: r.font(12),
                                  fontWeight: FontWeight.w900,
                                  color: isPractice
                                      ? Colors.white
                                      : Colors.grey[500],
                                )),
                          ],
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            SizedBox(height: r.spacing(4)),
            if (totalPages > 0)
              Padding(
                padding: EdgeInsets.only(right: r.spacing(22)),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('Hal ${currentPage + 1} / $totalPages',
                      style: GoogleFonts.comicNeue(
                        fontSize: r.font(10),
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      )),
                ),
              ),
          ],
        ),
      );
}