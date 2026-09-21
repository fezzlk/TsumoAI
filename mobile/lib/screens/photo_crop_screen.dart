import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Full-screen manual selection of one rectangular region of the captured
/// photo — the FEZ-93 recovery flow for when the whole-photo tile detector
/// (`segmentTilesWithHintsForExpectedCount`) picks up something that isn't
/// a tile (e.g. a reflection off the table edge). Excluding that area and
/// re-running detection on just the region that actually contains the
/// tiles is cheaper and more predictable than trying to make the detector
/// itself robust to it, and stays entirely on-device (no server/
/// generative-AI call — see the adopted policy on FEZ-93).
///
/// Unlike `TileBoxEditorScreen`'s `TileQuad` (a general quadrilateral, for
/// one already-detected tile that may have been photographed at an angle),
/// this selects a plain axis-aligned `Rect` of the *whole* photo — the
/// region still gets fed back through the same detector, which already
/// handles tilt/curvature within it.
///
/// Returns the selected [Rect] (in the photo's own pixel space) via
/// `Navigator.pop` on confirm, or `null` on cancel (back button/gesture).
class PhotoCropScreen extends StatefulWidget {
  final Uint8List rawImageBytes;
  final int rawWidth;
  final int rawHeight;
  final Rect initialRegion;

  const PhotoCropScreen({
    super.key,
    required this.rawImageBytes,
    required this.rawWidth,
    required this.rawHeight,
    required this.initialRegion,
  });

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

enum _CropHandle { topLeft, topRight, bottomLeft, bottomRight, body }

/// Wraps [child] in a drag area that reports deltas via [onDragDelta],
/// tracking exactly one pointer at a time. Plain `GestureDetector.onPanUpdate`
/// fires once per *moving* pointer inside its area — so two fingers landing
/// on the same handle/body region (an easy accident with a natural two-
/// handed hold-and-drag) each report their own delta for the same frame,
/// and a handler that applies every delta it receives ends up moving twice
/// as far as either finger actually moved. Tracking only the first pointer
/// until it lifts, and ignoring any other pointer in the meantime, avoids
/// that while leaving ordinary single-finger dragging unchanged.
class _SinglePointerDragArea extends StatefulWidget {
  final Widget child;
  final ValueChanged<Offset> onDragDelta;
  const _SinglePointerDragArea({
    required this.child,
    required this.onDragDelta,
  });

  @override
  State<_SinglePointerDragArea> createState() =>
      _SinglePointerDragAreaState();
}

class _SinglePointerDragAreaState extends State<_SinglePointerDragArea> {
  int? _activePointer;
  Offset? _lastPosition;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (_activePointer != null) return;
        _activePointer = event.pointer;
        _lastPosition = event.position;
      },
      onPointerMove: (event) {
        if (event.pointer != _activePointer || _lastPosition == null) return;
        widget.onDragDelta(event.position - _lastPosition!);
        _lastPosition = event.position;
      },
      onPointerUp: (event) {
        if (event.pointer != _activePointer) return;
        _activePointer = null;
        _lastPosition = null;
      },
      onPointerCancel: (event) {
        if (event.pointer != _activePointer) return;
        _activePointer = null;
        _lastPosition = null;
      },
      child: widget.child,
    );
  }
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  late Rect _region = widget.initialRegion;

  static const double _handleSize = 52;
  // A degenerate (near-zero) region would crop to nothing and make
  // re-detection meaningless; this is a generous floor, not a precision
  // limit — the detector itself handles the real fitting.
  static const double _minSize = 40;

  void _moveHandle(_CropHandle handle, Offset imageDelta) {
    final maxW = widget.rawWidth.toDouble();
    final maxH = widget.rawHeight.toDouble();

    setState(() {
      if (handle == _CropHandle.body) {
        // Preserve size exactly while clamping position — matches
        // `TileBoxEditorScreen`'s `panRegion`, so a drag that hits the
        // photo's edge stops there instead of shrinking the selection.
        final shifted = _region.shift(imageDelta);
        final left = shifted.width >= maxW
            ? (maxW - shifted.width) / 2
            : shifted.left.clamp(0.0, maxW - shifted.width);
        final top = shifted.height >= maxH
            ? (maxH - shifted.height) / 2
            : shifted.top.clamp(0.0, maxH - shifted.height);
        _region = Rect.fromLTWH(left, top, shifted.width, shifted.height);
        return;
      }

      final dragged = switch (handle) {
        _CropHandle.topLeft => Rect.fromLTRB(
            _region.left + imageDelta.dx,
            _region.top + imageDelta.dy,
            _region.right,
            _region.bottom,
          ),
        _CropHandle.topRight => Rect.fromLTRB(
            _region.left,
            _region.top + imageDelta.dy,
            _region.right + imageDelta.dx,
            _region.bottom,
          ),
        _CropHandle.bottomLeft => Rect.fromLTRB(
            _region.left + imageDelta.dx,
            _region.top,
            _region.right,
            _region.bottom + imageDelta.dy,
          ),
        _CropHandle.bottomRight => Rect.fromLTRB(
            _region.left,
            _region.top,
            _region.right + imageDelta.dx,
            _region.bottom + imageDelta.dy,
          ),
        _CropHandle.body => _region,
      };

      // Each dragged edge is clamped against the OPPOSITE edge's own
      // (unchanged-this-drag) position, not the other edge's own clamped
      // result — so a corner can never cross past its opposite corner,
      // and the opposite corner never gets dragged along as a side effect.
      final left = dragged.left.clamp(0.0, dragged.right - _minSize);
      final top = dragged.top.clamp(0.0, dragged.bottom - _minSize);
      final right = dragged.right.clamp(dragged.left + _minSize, maxW);
      final bottom = dragged.bottom.clamp(dragged.top + _minSize, maxH);
      _region = Rect.fromLTRB(left, top, right, bottom);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('範囲を切り抜いて再検出'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _region),
            child: const Text(
              '確定',
              style: TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewW = constraints.maxWidth;
              final viewH = constraints.maxHeight;
              final photoAspect = widget.rawWidth / widget.rawHeight;
              final viewAspect = viewW / viewH;

              late final double dispW, dispH;
              if (photoAspect > viewAspect) {
                dispW = viewW;
                dispH = viewW / photoAspect;
              } else {
                dispH = viewH;
                dispW = viewH * photoAspect;
              }
              final dispLeft = (viewW - dispW) / 2;
              final dispTop = (viewH - dispH) / 2;
              final scale = dispW / widget.rawWidth;

              Offset toScreen(Offset p) =>
                  Offset(dispLeft + p.dx * scale, dispTop + p.dy * scale);
              Offset toImageDelta(Offset screenDelta) => screenDelta / scale;

              Widget handle(_CropHandle h, Offset point) {
                final sp = toScreen(point);
                return Positioned(
                  left: sp.dx - _handleSize / 2,
                  top: sp.dy - _handleSize / 2,
                  width: _handleSize,
                  height: _handleSize,
                  child: _SinglePointerDragArea(
                    onDragDelta: (delta) =>
                        _moveHandle(h, toImageDelta(delta)),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.6),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                );
              }

              final regionScreenRect = Rect.fromLTWH(
                toScreen(_region.topLeft).dx,
                toScreen(_region.topLeft).dy,
                _region.width * scale,
                _region.height * scale,
              );

              return ClipRect(
                child: Stack(
                  children: [
                    Positioned(
                      left: dispLeft,
                      top: dispTop,
                      width: dispW,
                      height: dispH,
                      child: Image.memory(
                        widget.rawImageBytes,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                      ),
                    ),
                    // Dims everything outside the selected region so it's
                    // visually obvious what will (and won't) be fed to
                    // re-detection.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _CropMaskPainter(
                            regionRect: regionScreenRect,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: regionScreenRect.left,
                      top: regionScreenRect.top,
                      width: regionScreenRect.width,
                      height: regionScreenRect.height,
                      child: _SinglePointerDragArea(
                        onDragDelta: (delta) => _moveHandle(
                          _CropHandle.body,
                          toImageDelta(delta),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.orangeAccent,
                              width: 2.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    handle(_CropHandle.topLeft, _region.topLeft),
                    handle(_CropHandle.topRight, _region.topRight),
                    handle(_CropHandle.bottomLeft, _region.bottomLeft),
                    handle(_CropHandle.bottomRight, _region.bottomRight),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 8,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '牌が写っている範囲を指定してください',
                              style: TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CropMaskPainter extends CustomPainter {
  final Rect regionRect;
  _CropMaskPainter({required this.regionRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()..addRect(regionRect);
    final diff = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(diff, paint);
  }

  @override
  bool shouldRepaint(covariant _CropMaskPainter oldDelegate) =>
      oldDelegate.regionRect != regionRect;
}
