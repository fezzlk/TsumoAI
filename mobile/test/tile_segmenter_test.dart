import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tsumoai_mobile/services/tile_segmenter.dart';

img.Image _darkBackground(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(20, 90, 40));
  return image;
}

void _fillTile(img.Image image, int x, int y, int w, int h) {
  img.fillRect(image, x1: x, y1: y, x2: x + w - 1, y2: y + h - 1, color: img.ColorRgb8(240, 240, 235));
}

img.Image? _loadCaseImage(String name) {
  final file = File('../data/eval_images_cropped/$name.jpg');
  if (!file.existsSync()) return null;
  return img.decodeImage(file.readAsBytesSync());
}

void _fillRotatedTile(img.Image image, double cx, double cy, double w, double h, double angleDeg) {
  final rad = angleDeg * math.pi / 180.0;
  final cosA = math.cos(rad), sinA = math.sin(rad);
  final corners = [
    (-w / 2, -h / 2),
    (w / 2, -h / 2),
    (w / 2, h / 2),
    (-w / 2, h / 2),
  ].map((c) {
    final rx = c.$1 * cosA - c.$2 * sinA;
    final ry = c.$1 * sinA + c.$2 * cosA;
    return img.Point(cx + rx, cy + ry);
  }).toList();
  img.fillPolygon(image, vertices: corners, color: img.ColorRgb8(240, 240, 235));
}

typedef _PlacedTile = ({double cx, double cy, double w, double h, double angleDeg});

/// Places [nTiles] tiles left-to-right: the first [straightCount] axis-
/// aligned via [_fillTile] on a straight line, then the remainder curving
/// via [_fillRotatedTile] with a heading that ramps linearly from 0deg to
/// [totalBendDeg] — simulating a bent (non-straight) physical tile row.
/// Returns each tile's true (possibly rotated) placement, in the same order
/// tiles were placed (left to right); see [_pointInTile] for testing
/// whether a point falls within a given tile's *actual* rotated footprint
/// (its axis-aligned bounding box is not a safe proxy at these angles: two
/// neighboring tiles' bboxes can legitimately overlap even though the
/// tiles themselves don't).
List<_PlacedTile> _fillCurvedRun(
  img.Image image, {
  required int nTiles,
  required int straightCount,
  required double tileW,
  required double tileH,
  required double pitch,
  required double startX,
  required double startY,
  required double totalBendDeg,
}) {
  final placed = <_PlacedTile>[];
  var cx = startX + tileW / 2;
  var cy = startY;
  final bendTiles = nTiles - straightCount;
  for (int i = 0; i < nTiles; i++) {
    if (i < straightCount) {
      final x = (cx - tileW / 2).round();
      final y = (cy - tileH / 2).round();
      _fillTile(image, x, y, tileW.round(), tileH.round());
      placed.add((cx: cx, cy: cy, w: tileW, h: tileH, angleDeg: 0.0));
      cx += pitch;
    } else {
      final heading = totalBendDeg * (i - straightCount + 1) / bendTiles;
      _fillRotatedTile(image, cx, cy, tileW, tileH, heading);
      placed.add((cx: cx, cy: cy, w: tileW, h: tileH, angleDeg: heading));
      final rad = heading * math.pi / 180.0;
      cx += pitch * math.cos(rad);
      cy += pitch * math.sin(rad);
    }
  }
  return placed;
}

/// Whether [p] falls within [tile]'s actual (possibly rotated) footprint,
/// via inverse-rotation into the tile's own local axes.
bool _pointInTile(Offset p, _PlacedTile tile) {
  final rad = -tile.angleDeg * math.pi / 180.0;
  final dx = p.dx - tile.cx, dy = p.dy - tile.cy;
  final lx = dx * math.cos(rad) - dy * math.sin(rad);
  final ly = dx * math.sin(rad) + dy * math.cos(rad);
  return lx.abs() <= tile.w / 2 && ly.abs() <= tile.h / 2;
}

double _whiteFraction(img.Image image) {
  int white = 0, total = 0;
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final px = image.getPixel(x, y);
      final r = px.r.toInt(), g = px.g.toInt(), b = px.b.toInt();
      final maxC = math.max(r, math.max(g, b));
      final minC = math.min(r, math.min(g, b));
      final sat = maxC > 0 ? ((maxC - minC) * 255) ~/ maxC : 0;
      if (maxC >= 160 && sat <= 80) white++;
      total++;
    }
  }
  return total == 0 ? 0.0 : white / total;
}

void main() {
  test('segmentTiles counts non-touching rectangles', () {
    const width = 3000, height = 400;
    final canvas = _darkBackground(width, height);
    const tileW = 180, tileH = 300, gap = 40;
    var x = 50;
    for (int i = 0; i < 8; i++) {
      _fillTile(canvas, x, 50, tileW, tileH);
      x += tileW + gap;
    }

    final boxes = segmentTiles(canvas);

    expect(boxes.length, 8);
  });

  test('segmentTiles recovers count from touching rectangles', () {
    // Regression test for the original undercounting bug: tiles placed with
    // only a faint (sub-morphological-kernel) gap at a regular pitch used to
    // merge into one connected component after MORPH_CLOSE and get badly
    // undercounted by fixed-aspect-ratio subdivision.
    const width = 550;
    // The gap must be small enough for the 5x5-in-downscaled-space
    // morphological CLOSE to bridge it (segmentTiles downsamples by 4x), but
    // large enough to reliably survive nearest-pixel downsampling itself.
    const tileW = 500, tileH = 340, gap = 16;
    const pitch = tileH + gap;
    const nTiles = 14;
    final height = 20 + nTiles * pitch + 40;
    final canvas = _darkBackground(width, height);
    for (int i = 0; i < nTiles; i++) {
      _fillTile(canvas, 25, 20 + i * pitch, tileW, tileH);
    }

    final boxes = segmentTiles(canvas);

    expect(boxes.length, nTiles);
  });

  test('segmentTiles drops an unrelated blob past fourteen', () {
    // A stray white blob disconnected from the tile run (e.g. a spare tile
    // left in frame) must not inflate the count past the known 13/14 hand
    // size.
    const width = 600;
    const tileW = 500, tileH = 340, gap = 16;
    const pitch = tileH + gap;
    const nTiles = 14;
    final height = 20 + nTiles * pitch + 150 + 420 + 50;
    final canvas = _darkBackground(width, height);
    for (int i = 0; i < nTiles; i++) {
      _fillTile(canvas, 25, 20 + i * pitch, tileW, tileH);
    }
    final strayY = 20 + nTiles * pitch + 150;
    _fillTile(canvas, 40, strayY, 400, 420);

    final boxes = segmentTiles(canvas);

    expect(boxes.length, nTiles);
  });

  test('refineTileCrop straightens a tilted tile and trims background', () {
    const canvasW = 400, canvasH = 400;
    const tileW = 160.0, tileH = 220.0;
    const cx = 200.0, cy = 200.0;
    const angleDeg = 15.0;
    final canvas = _darkBackground(canvasW, canvasH);
    _fillRotatedTile(canvas, cx, cy, tileW, tileH, angleDeg);

    // Simulate a coarse per-slice detector's rough box: the axis-aligned
    // bounding box of the tilted tile (includes dark-background triangles
    // in its corners).
    final rad = angleDeg * math.pi / 180.0;
    final halfSpanX = (tileW / 2) * math.cos(rad).abs() + (tileH / 2) * math.sin(rad).abs();
    final halfSpanY = (tileW / 2) * math.sin(rad).abs() + (tileH / 2) * math.cos(rad).abs();
    final roughBox = Rect.fromLTWH(cx - halfSpanX, cy - halfSpanY, halfSpanX * 2, halfSpanY * 2);

    final naive = img.copyCrop(
      canvas,
      x: roughBox.left.round(),
      y: roughBox.top.round(),
      width: roughBox.width.round(),
      height: roughBox.height.round(),
    );
    final refined = refineTileCrop(canvas, roughBox);

    final naiveFraction = _whiteFraction(naive);
    final refinedFraction = _whiteFraction(refined);

    expect(refinedFraction, greaterThan(naiveFraction + 0.1),
        reason: 'straightened+tight crop should contain noticeably less background than the naive rough-box crop');
    expect(refinedFraction, greaterThan(0.8),
        reason: 'straightened+tight crop should be mostly tile, not background');
  });

  test('segmentTiles keeps each slot aligned to one tile on a curved (bent) row', () {
    // Regression test for the curved-row bug: the last few tiles of a
    // physical hand bend away from a straight line (confirmed on real
    // device photos), and the old fixed-cross-axis-per-slice subdivision
    // let a slice's box drift onto a neighboring tile plus background.
    const nTiles = 14;
    const straightCount = 10;
    const runExtent = 340.0, crossExtent = 500.0, gap = 80.0;
    const pitch = runExtent + gap;
    const totalBendDeg = 30.0;
    const startX = 100.0, startY = 1400.0;
    final canvas = _darkBackground(6000, 3000);
    final groundTruth = _fillCurvedRun(
      canvas,
      nTiles: nTiles,
      straightCount: straightCount,
      tileW: runExtent,
      tileH: crossExtent,
      pitch: pitch,
      startX: startX,
      startY: startY,
      totalBendDeg: totalBendDeg,
    );

    final boxes = segmentTiles(canvas);

    expect(boxes.length, nTiles, reason: 'curved row should still resolve to the correct 13/14 hand size');

    // For each detected box, sample a grid of points and classify each by
    // which ground-truth tile's actual (rotated) footprint it falls in.
    // This directly measures "how much of this crop belongs to the wrong
    // tile" — the real symptom confirmed on real device photos — without
    // relying on axis-aligned bbox overlap, which is not a safe proxy for
    // rotated neighbors (two rotated tiles' bboxes can overlap even when
    // the tiles themselves don't).
    const gridN = 8;
    for (final box in boxes) {
      final counts = List<int>.filled(groundTruth.length, 0);
      var total = 0;
      for (int gi = 0; gi < gridN; gi++) {
        for (int gj = 0; gj < gridN; gj++) {
          final p = Offset(
            box.left + box.width * (gi + 0.5) / gridN,
            box.top + box.height * (gj + 0.5) / gridN,
          );
          total++;
          for (int t = 0; t < groundTruth.length; t++) {
            if (_pointInTile(p, groundTruth[t])) {
              counts[t]++;
              break; // tiles don't physically overlap; first match is the owner
            }
          }
        }
      }
      final maxCount = counts.reduce(math.max);
      final matchIdx = counts.indexOf(maxCount);
      final matchFraction = maxCount / total;
      expect(matchFraction, greaterThan(0.5),
          reason: 'detected box $box should be dominated by a single tile '
              '(best match tile $matchIdx covers ${(matchFraction * 100).toStringAsFixed(0)}%)');
      for (int t = 0; t < groundTruth.length; t++) {
        if (t == matchIdx) continue;
        final fraction = counts[t] / total;
        expect(fraction, lessThan(0.2),
            reason: 'detected box $box should not substantially contain neighboring tile $t '
                '(${(fraction * 100).toStringAsFixed(0)}%)');
      }
    }
  });

  test('segmentTiles on real photos finds exactly fourteen', () {
    for (final name in ['case-001', 'case-002', 'case-003', 'case-004', 'case-005', 'case-006']) {
      final image = _loadCaseImage(name);
      if (image == null) continue; // eval fixture not present in this environment
      final rgb = image.numChannels == 3 ? image : image.convert(numChannels: 3);
      final boxes = segmentTiles(rgb);
      expect(boxes.length, 14, reason: '$name should detect exactly 14 tiles');
    }
  });
}
