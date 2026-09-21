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

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  late Rect _region = widget.initialRegion;

  static const double _handleSize = 52;
  // A degenerate (near-zero) region would crop to nothing and make
  // re-detection meaningless; this is a generous floor, not a precision
  // limit — the detector itself handles the real fitting.
  static const double _minSize = 40;

  // Each of the 4 corner handles and the body tracks its OWN single
  // pointer — two DIFFERENT corners being dragged by two different fingers
  // at once is legitimate (each moves independently and the results just
  // compose, like resizing with a pinch), so that stays allowed. What
  // isn't coherent is a corner resize and a whole-box move happening at
  // once, so `_bodyActive`/`_anyHandleActive` below block that combination
  // in either direction.
  //
  // Every active handle recomputes the edge(s) it owns from `_dragBaseline`
  // — the region snapshot from the moment the current (possibly multi-
  // touch) gesture started — plus that handle's OWN total on-screen
  // displacement since ITS OWN pointer went down, rather than adding this
  // event's incremental delta onto whatever `_region` happens to be right
  // now. That distinction matters once two handles share an edge: topLeft
  // and bottomLeft both own `left`. Incremental deltas applied to the live
  // `_region` compound — swipe both fingers left by the same amount and
  // the first handle's move already shifted `left`, so the second handle's
  // "move left by the same amount again" lands on top of that, doubling
  // the edge's total movement for one matching pair of finger swipes.
  // Recomputing `left` fresh from the fixed baseline each event makes
  // every handle's contribution depend only on its own displacement, never
  // on another handle's already-applied one — so two fingers moving the
  // same edge by the same amount converge on that one amount instead of
  // adding.
  Rect? _dragBaseline;
  final Map<_CropHandle, int> _activePointers = {};
  final Map<_CropHandle, Offset> _pointerDownPositions = {};

  bool get _bodyActive => _activePointers.containsKey(_CropHandle.body);
  bool get _anyHandleActive =>
      _activePointers.keys.any((h) => h != _CropHandle.body);

  void _onPointerDown(_CropHandle handle, PointerDownEvent event) {
    if (_activePointers.containsKey(handle)) return;
    if (handle == _CropHandle.body ? _anyHandleActive : _bodyActive) return;
    _dragBaseline ??= _region;
    _activePointers[handle] = event.pointer;
    _pointerDownPositions[handle] = event.position;
  }

  void _onPointerMove(_CropHandle handle, PointerMoveEvent event, double scale) {
    if (_activePointers[handle] != event.pointer) return;
    final downPosition = _pointerDownPositions[handle];
    final baseline = _dragBaseline;
    if (downPosition == null || baseline == null) return;
    final totalDelta = (event.position - downPosition) / scale;
    setState(() => _region = _applyHandle(handle, baseline, totalDelta));
  }

  void _onPointerEnd(_CropHandle handle, PointerEvent event) {
    if (_activePointers[handle] != event.pointer) return;
    _activePointers.remove(handle);
    _pointerDownPositions.remove(handle);
    if (_activePointers.isEmpty) _dragBaseline = null;
  }

  /// The region after applying [handle]'s total on-screen displacement
  /// ([totalDelta], image-space, measured from that handle's own pointer-
  /// down) to [baseline]. Only the 1–2 edges [handle] owns are touched —
  /// the rest come from the CURRENT `_region`, so another simultaneously-
  /// active handle's own contribution (applied by its own earlier call to
  /// this same method, this same frame or an earlier one) is preserved
  /// rather than reset back to the baseline's values for those edges.
  Rect _applyHandle(_CropHandle handle, Rect baseline, Offset totalDelta) {
    final maxW = widget.rawWidth.toDouble();
    final maxH = widget.rawHeight.toDouble();

    if (handle == _CropHandle.body) {
      // Preserve size exactly while clamping position — matches
      // `TileBoxEditorScreen`'s `panRegion`, so a drag that hits the
      // photo's edge stops there instead of shrinking the selection.
      final shifted = baseline.shift(totalDelta);
      final left = shifted.width >= maxW
          ? (maxW - shifted.width) / 2
          : shifted.left.clamp(0.0, maxW - shifted.width);
      final top = shifted.height >= maxH
          ? (maxH - shifted.height) / 2
          : shifted.top.clamp(0.0, maxH - shifted.height);
      return Rect.fromLTWH(left, top, shifted.width, shifted.height);
    }

    final current = _region;
    final rawLeft =
        handle == _CropHandle.topLeft || handle == _CropHandle.bottomLeft
        ? baseline.left + totalDelta.dx
        : current.left;
    final rawTop =
        handle == _CropHandle.topLeft || handle == _CropHandle.topRight
        ? baseline.top + totalDelta.dy
        : current.top;
    final rawRight =
        handle == _CropHandle.topRight || handle == _CropHandle.bottomRight
        ? baseline.right + totalDelta.dx
        : current.right;
    final rawBottom =
        handle == _CropHandle.bottomLeft || handle == _CropHandle.bottomRight
        ? baseline.bottom + totalDelta.dy
        : current.bottom;

    // Each edge is clamped against the OPPOSITE edge's own (this-handle-
    // unowned) position, not the other edge's own clamped result — so a
    // corner can never cross past its opposite corner, and the opposite
    // corner never gets dragged along as a side effect.
    final left = rawLeft.clamp(0.0, rawRight - _minSize);
    final top = rawTop.clamp(0.0, rawBottom - _minSize);
    final right = rawRight.clamp(rawLeft + _minSize, maxW);
    final bottom = rawBottom.clamp(rawTop + _minSize, maxH);
    return Rect.fromLTRB(left, top, right, bottom);
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

              Widget handle(_CropHandle h, Offset point) {
                final sp = toScreen(point);
                return Positioned(
                  key: ValueKey('crop-handle-${h.name}'),
                  left: sp.dx - _handleSize / 2,
                  top: sp.dy - _handleSize / 2,
                  width: _handleSize,
                  height: _handleSize,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) => _onPointerDown(h, event),
                    onPointerMove: (event) => _onPointerMove(h, event, scale),
                    onPointerUp: (event) => _onPointerEnd(h, event),
                    onPointerCancel: (event) => _onPointerEnd(h, event),
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
                      key: const ValueKey('crop-handle-body'),
                      left: regionScreenRect.left,
                      top: regionScreenRect.top,
                      width: regionScreenRect.width,
                      height: regionScreenRect.height,
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (event) =>
                            _onPointerDown(_CropHandle.body, event),
                        onPointerMove: (event) =>
                            _onPointerMove(_CropHandle.body, event, scale),
                        onPointerUp: (event) =>
                            _onPointerEnd(_CropHandle.body, event),
                        onPointerCancel: (event) =>
                            _onPointerEnd(_CropHandle.body, event),
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
