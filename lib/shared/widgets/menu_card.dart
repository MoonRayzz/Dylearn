// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:google_fonts/google_fonts.dart';

class MenuCard extends StatelessWidget {
  final String title;
  final String animationPath;
  final VoidCallback onTap;
  final bool isPrimary;

  const MenuCard({
    super.key,
    required this.title,
    required this.animationPath,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final Color cardColor =
        isPrimary ? const Color(0xFFFF9F1C) : colorScheme.secondary;
    final Color textColor = isPrimary ? Colors.white : Colors.black87;

    return Semantics(
      label: "Tombol Menu $title",
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          splashColor: cardColor.withOpacity(0.3),
          // FIX: ganti AnimatedContainer → Container
          // isPrimary tidak pernah berubah saat runtime sehingga AnimatedContainer
          // tidak pernah benar-benar menganimasikan apapun, tapi Flutter tetap
          // mendaftarkan ticker internal yang sia-sia.
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: RepaintBoundary(
                      child: Lottie.asset(
                        animationPath,
                        fit: BoxFit.contain,
                        frameRate: FrameRate.composition,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            isPrimary
                                ? Icons.camera_alt_rounded
                                : Icons.extension_rounded,
                            size: 48,
                            color: textColor.withOpacity(0.8),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: 20.0, left: 12, right: 12),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.comicNeue(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      height: 1.1,
                    ),
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