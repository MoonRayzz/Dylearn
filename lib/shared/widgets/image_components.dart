// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ImageViewer extends StatefulWidget {
  final String url;
  final VoidCallback? onLoaded;

  const ImageViewer({super.key, required this.url, this.onLoaded});

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  static final BoxDecoration _decoration = BoxDecoration(
    borderRadius: BorderRadius.circular(20),
    boxShadow: const [
      BoxShadow(color: Colors.black54, blurRadius: 15, offset: Offset(0, 8))
    ],
  );
  static final BorderRadius _clipRadius = BorderRadius.circular(20);

  bool _onLoadedFired = false;

  @override
  void didUpdateWidget(ImageViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      _onLoadedFired = false;
    }
  }

  void _fireOnLoaded() {
    if (_onLoadedFired || widget.onLoaded == null) return;
    _onLoadedFired = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLoaded!();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) return const SizedBox();
    final bool isLocal = !widget.url.startsWith('http');

    return Container(
      decoration: _decoration,
      child: ClipRRect(
        borderRadius: _clipRadius,
        child: isLocal
            ? Image.file(
                File(widget.url),
                fit: BoxFit.contain,
                cacheWidth: 800,
                frameBuilder: (ctx, child, frame, _) {
                  if (frame != null) _fireOnLoaded();
                  return child;
                },
                errorBuilder: (c, e, s) => const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 50,
                ),
              )
            : CachedNetworkImage(
                imageUrl: widget.url,
                fit: BoxFit.contain,
                memCacheWidth: 800,
                imageBuilder: (context, provider) {
                  _fireOnLoaded();
                  return Image(image: provider, fit: BoxFit.contain);
                },
                placeholder: (c, u) => const Center(
                  child: CircularProgressIndicator(color: Colors.orange),
                ),
                errorWidget: (c, e, s) => const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 50,
                ),
              ),
      ),
    );
  }
}

class ZoomableFullscreenImage extends StatefulWidget {
  final String url;
  final Function(bool) onZoomChanged;

  const ZoomableFullscreenImage({
    super.key,
    required this.url,
    required this.onZoomChanged,
  });

  @override
  State<ZoomableFullscreenImage> createState() => _ZoomableFullscreenImageState();
}

class _ZoomableFullscreenImageState extends State<ZoomableFullscreenImage>
    with SingleTickerProviderStateMixin {
  late TransformationController _tc;
  late AnimationController _ac;
  Animation<Matrix4>? _anim;
  TapDownDetails? _doubleTapDetails;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _tc = TransformationController();
    _tc.addListener(() {
      final isZoomed = _tc.value.getMaxScaleOnAxis() > 1.01;
      if (_zoomed != isZoomed) {
        _zoomed = isZoomed;
        widget.onZoomChanged(isZoomed);
      }
    });
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
        if (_anim != null) _tc.value = _anim!.value;
      });
  }

  @override
  void dispose() {
    _tc.dispose();
    _ac.dispose();
    super.dispose();
  }

  void _onDoubleTapDown(TapDownDetails d) => _doubleTapDetails = d;

  void _onDoubleTap() {
    if (_ac.isAnimating) return;
    final pos = _doubleTapDetails!.localPosition;
    const scale = 3.0;
    final isZoomed = _tc.value.getMaxScaleOnAxis() > 1.01;
    final Matrix4 end = isZoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
          ..translate(-pos.dx * (scale - 1), -pos.dy * (scale - 1))
          ..scale(scale));

    _anim = Matrix4Tween(begin: _tc.value, end: end)
        .animate(CurveTween(curve: Curves.easeInOut).animate(_ac));
    _ac.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onDoubleTapDown: _onDoubleTapDown,
        onDoubleTap: _onDoubleTap,
        child: InteractiveViewer(
          transformationController: _tc,
          minScale: 1.0,
          maxScale: 5.0,
          child: widget.url.startsWith('http')
              ? CachedNetworkImage(imageUrl: widget.url, fit: BoxFit.contain)
              : Image.file(File(widget.url), fit: BoxFit.contain),
        ),
      );
}