import 'dart:io';

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
