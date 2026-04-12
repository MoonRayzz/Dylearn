// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

class ReadingRuler extends StatefulWidget {
  final double opacity;

  const ReadingRuler({
    super.key,
    required this.opacity,
  });

  @override
  State<ReadingRuler> createState() => _ReadingRulerState();
}

class _ReadingRulerState extends State<ReadingRuler> {
  late final ValueNotifier<double> _positionNotifier;

  // FIX: dijadikan static const — tidak perlu dialokasikan per-instance
  static const double _rulerHeight = 60.0;

  @override
  void initState() {
    super.initState();
    _positionNotifier = ValueNotifier<double>(200.0);
  }

  @override
  void dispose() {
    _positionNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;

    return ValueListenableBuilder<double>(
      valueListenable: _positionNotifier,
      builder: (context, currentPos, _) {
        return Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              width: screenWidth,
              height: currentPos,
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withOpacity(widget.opacity),
                ),
              ),
            ),
            Positioned(
              top: currentPos + _rulerHeight,
              left: 0,
              width: screenWidth,
              height: screenHeight - (currentPos + _rulerHeight),
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withOpacity(widget.opacity),
                ),
              ),
            ),
            Positioned(
              top: currentPos - 10,
              left: 0,
              width: screenWidth,
              height: _rulerHeight + 20,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: (details) {
                  final double newPos =
                      _positionNotifier.value + details.delta.dy;
                  if (newPos > 80 && newPos < screenHeight - 180) {
                    _positionNotifier.value = newPos;
                  }
                },
                child: Container(
                  alignment: Alignment.center,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.05),
                      border: Border.symmetric(
                        horizontal: BorderSide(
                          color: Colors.orange.withOpacity(0.4),
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: const Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.only(right: 12.0),
                        child: Icon(
                          Icons.unfold_more_rounded,
                          size: 20,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}