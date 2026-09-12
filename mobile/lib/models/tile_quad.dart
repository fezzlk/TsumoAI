import 'dart:math' as math;
import 'package:flutter/material.dart' show Offset, Rect;

import 'tile_observation.dart';

/// A single tile's crop region as four independently-movable corners,
/// rather than an axis-aligned [Rect]. Needed because a tile photographed
/// at an angle projects as a general quadrilateral (perspective
/// foreshortening), not just a rotated rectangle — a plain rotated-rect
/// model can't represent that, but four free corners can.
class TileQuad {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomLeft;
  final Offset bottomRight;

  const TileQuad({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  /// The common case: an axis-aligned box (e.g. straight from
  /// `segmentTiles`) is just a degenerate quad with right-angle corners.
  factory TileQuad.fromRect(Rect r) => TileQuad(
    topLeft: r.topLeft,
    topRight: r.topRight,
    bottomLeft: r.bottomLeft,
    bottomRight: r.bottomRight,
  );

  Offset get center => Offset(
    (topLeft.dx + topRight.dx + bottomLeft.dx + bottomRight.dx) / 4,
    (topLeft.dy + topRight.dy + bottomLeft.dy + bottomRight.dy) / 4,
  );

  Rect get boundingRect {
    final xs = [topLeft.dx, topRight.dx, bottomLeft.dx, bottomRight.dx];
    final ys = [topLeft.dy, topRight.dy, bottomLeft.dy, bottomRight.dy];
    return Rect.fromLTRB(
      xs.reduce(math.min),
      ys.reduce(math.min),
      xs.reduce(math.max),
      ys.reduce(math.max),
    );
  }

  ObservationBoundingBox get observationBoundingBox {
    final rect = boundingRect;
    return ObservationBoundingBox(
      left: rect.left,
      top: rect.top,
      right: rect.right,
      bottom: rect.bottom,
    );
  }

  /// Angle of the physical top edge in oriented-image coordinates.
  /// Positive values are clockwise because image +y points down.
  double get orientationDegrees {
    final radians = math.atan2(
      topRight.dy - topLeft.dy,
      topRight.dx - topLeft.dx,
    );
    final degrees = radians * 180 / math.pi;
    return ((degrees + 180) % 360) - 180;
  }

  TileQuad translate(Offset delta) => TileQuad(
    topLeft: topLeft + delta,
    topRight: topRight + delta,
    bottomLeft: bottomLeft + delta,
    bottomRight: bottomRight + delta,
  );

  /// Point-wise transform (e.g. between raw-display and corrected-image
  /// pixel spaces) — applies [f] to each corner independently.
  TileQuad mapPoints(Offset Function(Offset) f) => TileQuad(
    topLeft: f(topLeft),
    topRight: f(topRight),
    bottomLeft: f(bottomLeft),
    bottomRight: f(bottomRight),
  );

  TileQuad withCorner(TileQuadCorner corner, Offset value) {
    switch (corner) {
      case TileQuadCorner.topLeft:
        return TileQuad(
          topLeft: value,
          topRight: topRight,
          bottomLeft: bottomLeft,
          bottomRight: bottomRight,
        );
      case TileQuadCorner.topRight:
        return TileQuad(
          topLeft: topLeft,
          topRight: value,
          bottomLeft: bottomLeft,
          bottomRight: bottomRight,
        );
      case TileQuadCorner.bottomLeft:
        return TileQuad(
          topLeft: topLeft,
          topRight: topRight,
          bottomLeft: value,
          bottomRight: bottomRight,
        );
      case TileQuadCorner.bottomRight:
        return TileQuad(
          topLeft: topLeft,
          topRight: topRight,
          bottomLeft: bottomLeft,
          bottomRight: value,
        );
    }
  }
}

enum TileQuadCorner { topLeft, topRight, bottomLeft, bottomRight }
