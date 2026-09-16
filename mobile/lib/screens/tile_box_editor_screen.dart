import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/tile_quad.dart';

/// Full-screen manual correction of one tile's crop quadrilateral. Pushed
/// as its own route (not embedded in the scrollable results screen) so:
/// - the photo can fill the whole screen (large, precise dragging), and
/// - drag state lives entirely in this screen's own State, so per-frame
///   `setState` during a drag only repaints this screen — it can't trigger
///   expensive rebuilds elsewhere (e.g. re-encoding the other 13 crop
///   thumbnails on the results screen, which is what made the previous
///   embedded editor feel heavy).
///
/// The four corners move fully independently (no "opposite corner stays
/// fixed" coupling) so a tile photographed at an angle — which projects as
/// a general quadrilateral, not just a rotated rectangle — can be matched.
/// A fifth handle at the quad's center translates all four corners together,
/// for repositioning the whole box without reshaping it.
///
/// Returns the edited [TileQuad] (in the same pixel space as [initialQuad])
/// via `Navigator.pop` on confirm, or `null` on cancel.
class TileBoxEditorScreen extends StatefulWidget {
  final Uint8List rawImageBytes;
  final int rawWidth;
  final int rawHeight;
  final TileQuad initialQuad;

  const TileBoxEditorScreen({
    super.key,
    required this.rawImageBytes,
    required this.rawWidth,
    required this.rawHeight,
    required this.initialQuad,
  });

  @override
  State<TileBoxEditorScreen> createState() => _TileBoxEditorScreenState();
}

enum _DragMode { body, background }

class _TileBoxEditorScreenState extends State<TileBoxEditorScreen> {
  late TileQuad _quad = widget.initialQuad;

  // Starts zoomed in on the box being edited (its bounding rect padded out
  // to roughly 2x its own size) rather than fitting the whole photo — the
  // box is normally a small fraction of the frame, so fitting the whole
  // photo left handles small and imprecise to drag. Reframed (not just
  // fixed once) from the box's *current* position whenever the toggle
  // switches into zoomed-in mode (see the toggle button below), and
  // pannable in between via `panRegion` so a corner that lands outside the
  // initial frame is still reachable without dropping to the tiny
  // zoomed-out view.
  late Rect _focusRegion;
  bool _zoomedIn = true;
  _DragMode? _dragMode;

  static const double _handleSize = 52;

  @override
  void initState() {
    super.initState();
    _focusRegion = _computeFocusRegion(widget.initialQuad);
  }

  Rect _computeFocusRegion(TileQuad quad) {
    final box = quad.boundingRect;
    final pad = math.max(box.width, box.height) * 0.6;
    final expanded = box.inflate(pad);
    final left = expanded.left.clamp(0, widget.rawWidth.toDouble()).toDouble();
    final top = expanded.top.clamp(0, widget.rawHeight.toDouble()).toDouble();
    final right = expanded.right.clamp(0, widget.rawWidth.toDouble()).toDouble();
    final bottom = expanded.bottom.clamp(0, widget.rawHeight.toDouble()).toDouble();
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('枠を補正'),
        actions: [
          IconButton(
            onPressed: () => setState(() {
              _zoomedIn = !_zoomedIn;
              _focusRegion = _zoomedIn
                  ? _computeFocusRegion(_quad)
                  : Rect.fromLTWH(
                      0,
                      0,
                      widget.rawWidth.toDouble(),
                      widget.rawHeight.toDouble(),
                    );
            }),
            icon: Icon(_zoomedIn ? Icons.zoom_out_map : Icons.zoom_in_map),
            tooltip: _zoomedIn ? '全体表示' : '枠付近を拡大',
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _quad),
            child: const Text('確定', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
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
              final region = _focusRegion;
              final regionAspect = region.width / region.height;
              final viewAspect = viewW / viewH;

              late final double dispW, dispH;
              if (regionAspect > viewAspect) {
                dispW = viewW;
                dispH = viewW / regionAspect;
              } else {
                dispH = viewH;
                dispW = viewH * regionAspect;
              }
              final dispLeft = (viewW - dispW) / 2;
              final dispTop = (viewH - dispH) / 2;
              final scale = dispW / region.width;

              Offset toScreen(Offset p) =>
                  Offset(dispLeft + (p.dx - region.left) * scale, dispTop + (p.dy - region.top) * scale);

              Offset toImage(Offset screenPoint) =>
                  region.topLeft + (screenPoint - Offset(dispLeft, dispTop)) / scale;

              void moveCorner(TileQuadCorner corner, Offset current, Offset delta) {
                setState(() {
                  _quad = _quad.withCorner(corner, current + delta / scale);
                });
              }

              void moveAll(Offset delta) {
                setState(() {
                  _quad = _quad.translate(delta / scale);
                });
              }

              // Pans the visible region opposite the finger's motion ("content
              // follows the finger", matching moveCorner/moveAll's feel),
              // clamped so it never leaves the photo. When zoomed out the
              // region already spans the whole photo, so the clamp makes this
              // a natural no-op there.
              void panRegion(Offset screenDelta) {
                setState(() {
                  final imageDelta = screenDelta / scale;
                  final shifted = _focusRegion.shift(-imageDelta);
                  final maxW = widget.rawWidth.toDouble();
                  final maxH = widget.rawHeight.toDouble();
                  final left = shifted.width >= maxW
                      ? (maxW - shifted.width) / 2
                      : shifted.left.clamp(0.0, maxW - shifted.width);
                  final top = shifted.height >= maxH
                      ? (maxH - shifted.height) / 2
                      : shifted.top.clamp(0.0, maxH - shifted.height);
                  _focusRegion = Rect.fromLTWH(
                    left,
                    top,
                    shifted.width,
                    shifted.height,
                  );
                });
              }

              Widget handle(TileQuadCorner corner, Offset point) {
                final screenPoint = toScreen(point);
                return Positioned(
                  left: screenPoint.dx - _handleSize / 2,
                  top: screenPoint.dy - _handleSize / 2,
                  width: _handleSize,
                  height: _handleSize,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (details) => moveCorner(corner, point, details.delta),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black.withValues(alpha: 0.6), width: 2),
                      ),
                    ),
                  ),
                );
              }

              // Dragging inside the quad's body moves the whole box (like the
              // old centerHandle, but over the whole interior rather than a
              // small circle at the centroid — a fixed-size circle there
              // necessarily collides with the corner handles once the quad
              // is small, e.g. in the zoomed-out view, making it impossible
              // to grab reliably). Dragging outside the quad instead pans
              // the visible region, so a corner that's off-screen while
              // zoomed in can be brought into view. Placed before the corner
              // handles so a corner handle wins hit-testing when the two
              // overlap.
              Widget bodyAndBackgroundLayer() {
                return Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      _dragMode =
                          _quad.boundingRect.contains(
                            toImage(details.localPosition),
                          )
                          ? _DragMode.body
                          : _DragMode.background;
                    },
                    onPanUpdate: (details) {
                      if (_dragMode == _DragMode.body) {
                        moveAll(details.delta);
                      } else {
                        panRegion(details.delta);
                      }
                    },
                    onPanEnd: (_) => _dragMode = null,
                  ),
                );
              }

              // Purely cosmetic marker at the quad's center (no longer a
              // drag target itself — see bodyAndBackgroundLayer above).
              Widget centerGlyph(Offset point) {
                final screenPoint = toScreen(point);
                return Positioned(
                  left: screenPoint.dx - 12,
                  top: screenPoint.dy - 12,
                  width: 24,
                  height: 24,
                  child: const IgnorePointer(
                    child: Icon(
                      Icons.open_with,
                      size: 20,
                      color: Colors.orangeAccent,
                    ),
                  ),
                );
              }

              return ClipRect(
                child: Stack(
                  children: [
                    Positioned(
                      left: dispLeft - region.left * scale,
                      top: dispTop - region.top * scale,
                      width: widget.rawWidth * scale,
                      height: widget.rawHeight * scale,
                      child: Image.memory(widget.rawImageBytes, fit: BoxFit.fill, gaplessPlayback: true),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _QuadOutlinePainter(
                          topLeft: toScreen(_quad.topLeft),
                          topRight: toScreen(_quad.topRight),
                          bottomLeft: toScreen(_quad.bottomLeft),
                          bottomRight: toScreen(_quad.bottomRight),
                        ),
                      ),
                    ),
                    bodyAndBackgroundLayer(),
                    centerGlyph(_quad.center),
                    handle(TileQuadCorner.topLeft, _quad.topLeft),
                    handle(TileQuadCorner.topRight, _quad.topRight),
                    handle(TileQuadCorner.bottomLeft, _quad.bottomLeft),
                    handle(TileQuadCorner.bottomRight, _quad.bottomRight),
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
                              '内側をドラッグで移動 / 外側をドラッグで表示範囲を移動',
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

class _QuadOutlinePainter extends CustomPainter {
  final Offset topLeft, topRight, bottomLeft, bottomRight;
  _QuadOutlinePainter({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.orangeAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final path = Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(topRight.dx, topRight.dy)
      ..lineTo(bottomRight.dx, bottomRight.dy)
      ..lineTo(bottomLeft.dx, bottomLeft.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _QuadOutlinePainter oldDelegate) =>
      oldDelegate.topLeft != topLeft ||
      oldDelegate.topRight != topRight ||
      oldDelegate.bottomLeft != bottomLeft ||
      oldDelegate.bottomRight != bottomRight;
}
