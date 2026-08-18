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

  test('expectedPitch recovers a count that own-pitch detection cannot', () {
    // A single solid, gap-free blob has zero internal periodicity signal
    // (uniform brightness => zero autocorrelation variance => `_estimatePitch`
    // always returns null for it), so without a prior it can only ever be
    // reported as one undivided blob. An `expectedPitch` hint should let it
    // be resolved into the correct tile count anyway (FEZ-94).
    const width = 550, tileW = 500, tileH = 340, nTiles = 14;
    final height = nTiles * tileH;
    final canvas = _darkBackground(width, height);
    _fillTile(canvas, 25, 0, tileW, height);

    final withoutHint = segmentTiles(canvas);
    final withHint = segmentTiles(canvas, expectedPitch: tileH.toDouble());

    expect(withoutHint.length, isNot(nTiles),
        reason: 'a single featureless blob has no periodicity signal to recover the count from');
    expect(withHint.length, nTiles);
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
