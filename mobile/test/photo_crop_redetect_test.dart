// Regression test for FEZ-93's recovery flow: `ScanScreen._redetectInRegion`
// crops `_capturedImage` to a user-selected sub-region, re-runs
// `segmentTilesWithHintsForExpectedCount` on just that crop, then shifts
// the resulting boxes by the crop's own top-left offset to bring them back
// into the full photo's pixel space. This test doesn't touch `ScanScreen`
// itself (that needs a live camera controller); it verifies the underlying
// property the offset math depends on — that detecting within a padded
// crop of a tile row and shifting the result back reproduces the same
// boxes as detecting directly on the full photo.

import 'package:flutter/material.dart' show Offset, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tsumoai_mobile/services/tile_segmenter.dart';

img.Image _darkBackground(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(20, 90, 40));
  return image;
}

void _fillTile(img.Image image, int x, int y, int w, int h) {
  img.fillRect(
    image,
    x1: x,
    y1: y,
    x2: x + w - 1,
    y2: y + h - 1,
    color: img.ColorRgb8(240, 240, 235),
  );
}

/// Paints a straight horizontal row of [count] tiles onto [image], starting
/// at ([startX], [startY]), each [tileW]x[tileH] with [pitch] center-to-
/// center spacing. Returns the row's own bounding box (tight, no padding).
Rect _paintTileRow(
  img.Image image, {
  required int count,
  required int startX,
  required int startY,
  required int tileW,
  required int tileH,
  required int pitch,
}) {
  for (int i = 0; i < count; i++) {
    _fillTile(image, startX + i * pitch, startY, tileW, tileH);
  }
  final runWidth = (count - 1) * pitch + tileW;
  return Rect.fromLTWH(
    startX.toDouble(),
    startY.toDouble(),
    runWidth.toDouble(),
    tileH.toDouble(),
  );
}

Future<({List<Rect> boxes, List<double> angleHints})> _detect(
  img.Image image,
  int expectedTileCount,
) async {
  final bytes = img.encodeJpg(image);
  return segmentTilesWithHintsForExpectedCount(
    (bytes: bytes, expectedTileCount: expectedTileCount),
  );
}

void main() {
  test(
    'redetecting within a cropped region and shifting back matches detecting on the full photo',
    () async {
      const tileCount = 14;
      // Matches the gap/tile-size proportions already proven robust to
      // detection (and here, additionally, to JPEG re-encoding — this test
      // goes through `img.encodeJpg`/`decodeImage` exactly like the real
      // capture/crop flow does, unlike the plain-`img.Image` tests
      // elsewhere in this file) in the "segmentTiles honors each selected
      // count" test above.
      const tileW = 200, tileH = 300, gap = 20;
      const pitch = tileW + gap;
      const startX = 100, startY = 40;
      const imageW = startX + (tileCount - 1) * pitch + tileW + 100;
      const imageH = startY * 2 + tileH;

      final full = _darkBackground(imageW, imageH);
      _paintTileRow(
        full,
        count: tileCount,
        startX: startX,
        startY: startY,
        tileW: tileW,
        tileH: tileH,
        pitch: pitch,
      );

      final fullDetected = await _detect(full, tileCount);
      expect(fullDetected.boxes, hasLength(tileCount));

      // A padded crop around the row — as PhotoCropScreen would produce
      // when the user excludes some other part of the photo (e.g. a
      // reflection) but leaves generous margin around the actual tiles.
      const cropX = 50, cropY = 0;
      const cropW = imageW - cropX - 50;
      const cropH = imageH;
      final cropped = img.copyCrop(
        full,
        x: cropX,
        y: cropY,
        width: cropW,
        height: cropH,
      );
      final croppedDetected = await _detect(cropped, tileCount);
      expect(croppedDetected.boxes, hasLength(tileCount));

      final shiftedBoxes = [
        for (final box in croppedDetected.boxes)
          box.shift(Offset(cropX.toDouble(), cropY.toDouble())),
      ];

      for (int i = 0; i < tileCount; i++) {
        final expected = fullDetected.boxes[i];
        final actual = shiftedBoxes[i];
        expect(
          (actual.center - expected.center).distance,
          lessThan(3.0),
          reason: 'tile $i center should match after crop+shift',
        );
        expect(
          (actual.width - expected.width).abs(),
          lessThan(3.0),
          reason: 'tile $i width should match after crop+shift',
        );
        expect(
          (actual.height - expected.height).abs(),
          lessThan(3.0),
          reason: 'tile $i height should match after crop+shift',
        );
      }
    },
  );
}
