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
  // `_baseline` is a "commit point": every currently-active handle's
  // contribution to the edge(s) it owns is `_baseline.<field> +` that
  // handle's own on-screen displacement *since the last commit* (tracked
  // as `_lastKnownPosition[handle] - _referencePosition[handle]`), and a
  // shared edge with more than one active owner averages their
  // contributions. `_rebase()` — called on every pointer down/up that
  // changes which handles are active — sets `_baseline` to whatever
  // `_region` currently is and resets every still-active handle's
  // reference point to its current position, i.e. commits the exact
  // on-screen state at that instant and makes every remaining/new handle's
  // future movement purely incremental from there. Three things this
  // fixes, all from the same root cause (measuring against a single
  // baseline fixed at the very start of a whole multi-touch session,
  // instead of one that moves forward every time the situation changes):
  // - Two fingers sharing an edge, swiping the same direction by the same
  //   amount, no longer double that edge's movement (each averaged
  //   contribution is measured from the shared commit point, not stacked
  //   on the live, already-mutated region).
  // - Two fingers not in perfect lock-step no longer visibly jitter (their
  //   contributions are averaged, not whichever's event happened to fire
  //   last).
  // - Lifting one of two fingers on a shared edge, or lifting and
  //   re-touching the same handle mid-drag, no longer snaps that edge back
  //   toward (or to) its pre-drag position: without a fresh commit at the
  //   moment of the lift, the lifted handle's contribution simply
  //   vanishes from the average, leaving only the other (possibly
  //   stationary) handle's own baseline-relative value.
  late Rect _baseline = widget.initialRegion;
  final Map<_CropHandle, int> _activePointers = {};
  final Map<_CropHandle, Offset> _referencePosition = {};
  final Map<_CropHandle, Offset> _lastKnownPosition = {};

  bool get _bodyActive => _activePointers.containsKey(_CropHandle.body);
  bool get _anyHandleActive =>
      _activePointers.keys.any((h) => h != _CropHandle.body);

  void _rebase() {
    _baseline = _region;
    for (final h in _activePointers.keys) {
      _referencePosition[h] = _lastKnownPosition[h]!;
    }
  }

  void _onPointerDown(_CropHandle handle, PointerDownEvent event) {
    if (_activePointers.containsKey(handle)) return;
    if (handle == _CropHandle.body ? _anyHandleActive : _bodyActive) return;
    _activePointers[handle] = event.pointer;
    _lastKnownPosition[handle] = event.position;
    _rebase();
  }

  void _onPointerMove(_CropHandle handle, PointerMoveEvent event, double scale) {
    if (_activePointers[handle] != event.pointer) return;
    _lastKnownPosition[handle] = event.position;
    setState(() => _region = _computeRegion(scale));
  }

  void _onPointerEnd(_CropHandle handle, PointerEvent event) {
    if (_activePointers[handle] != event.pointer) return;
    _activePointers.remove(handle);
    _referencePosition.remove(handle);
    _lastKnownPosition.remove(handle);
    if (_activePointers.isEmpty) return;
    // Commits `_region` exactly as it is right now (removing this handle
    // doesn't change the CURRENT value, only what future moves are
    // measured from) — see the class-level doc comment for why this must
    // happen at every membership change, not just be left for the next
    // move event.
    _rebase();
  }

  /// The average, over every currently-active handle in [owners], of
  /// `_baseline.<field>` (via [field]) plus that handle's own on-screen
  /// displacement since the last [_rebase] ([isX]: dx component, else dy,
  /// scaled from screen to image space by [scale]) — or, when none of
  /// [owners] is currently active, [fallback] (the edge's current live
  /// value, so it stays put with no owner touching it).
  double _averagedEdge(
    List<_CropHandle> owners,
    double Function(Rect) field,
    bool isX,
    double fallback,
    double scale,
  ) {
    final active = owners.where(_activePointers.containsKey).toList();
    if (active.isEmpty) return fallback;
    var sum = 0.0;
    for (final h in active) {
      final d = (_lastKnownPosition[h]! - _referencePosition[h]!) / scale;
      sum += field(_baseline) + (isX ? d.dx : d.dy);
    }
    return sum / active.length;
  }

  /// The region after applying every currently-active handle's own
  /// displacement since the last [_rebase] to `_baseline` — see the
  /// class-level doc comment for why this recomputes fresh from every
  /// active handle each event (averaging a shared edge's contributions)
  /// rather than incrementally mutating the live `_region`.
  Rect _computeRegion(double scale) {
    final maxW = widget.rawWidth.toDouble();
    final maxH = widget.rawHeight.toDouble();

    if (_bodyActive) {
      final d =
          (_lastKnownPosition[_CropHandle.body]! -
              _referencePosition[_CropHandle.body]!) /
          scale;
      // Preserve size exactly while clamping position — matches
      // `TileBoxEditorScreen`'s `panRegion`, so a drag that hits the
      // photo's edge stops there instead of shrinking the selection.
      final shifted = _baseline.shift(d);
      final left = shifted.width >= maxW
          ? (maxW - shifted.width) / 2
          : shifted.left.clamp(0.0, maxW - shifted.width);
      final top = shifted.height >= maxH
          ? (maxH - shifted.height) / 2
          : shifted.top.clamp(0.0, maxH - shifted.height);
      return Rect.fromLTWH(left, top, shifted.width, shifted.height);
    }

    final current = _region;
    final rawLeft = _averagedEdge(
      [_CropHandle.topLeft, _CropHandle.bottomLeft],
      (r) => r.left,
      true,
      current.left,
      scale,
    );
    final rawTop = _averagedEdge(
      [_CropHandle.topLeft, _CropHandle.topRight],
      (r) => r.top,
      false,
      current.top,
      scale,
    );
    final rawRight = _averagedEdge(
      [_CropHandle.topRight, _CropHandle.bottomRight],
      (r) => r.right,
      true,
      current.right,
      scale,
    );
    final rawBottom = _averagedEdge(
      [_CropHandle.bottomLeft, _CropHandle.bottomRight],
      (r) => r.bottom,
      false,
      current.bottom,
      scale,
    );

    // Each edge is clamped against the OPPOSITE edge's own (independently
    // computed) position, not the other edge's own clamped result — so a
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
