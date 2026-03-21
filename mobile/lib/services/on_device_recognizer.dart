import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'tile_classifier.dart';

/// Result of on-device tile recognition.
class OnDeviceRecognitionResult {
  final List<String> tileCodes;
  final List<double> confidences;
  final double avgConfidence;

  OnDeviceRecognitionResult({
    required this.tileCodes,
    required this.confidences,
    required this.avgConfidence,
  });
}

/// On-device tile recognition pipeline.
///
/// Flow: JPEG → segment tiles (white-pixel connected components) → classify
/// each tile with TFLite MobileNetV2 → return tile codes.
class OnDeviceRecognizer {
  final TileClassifier _classifier = TileClassifier();
  bool _ready = false;

  bool get isReady => _ready;

  Future<void> init() async {
    if (_ready) return;
    await _classifier.init();
    _ready = _classifier.isReady;
  }

  /// Recognize tiles from a captured image file.
  /// Returns null if recognition fails (model not ready, too few tiles, etc).
  Future<OnDeviceRecognitionResult?> recognize(File imageFile) async {
    if (!_ready) return null;

    final bytes = await imageFile.readAsBytes();

    // Decode + segment + classify in an isolate to avoid blocking the UI
    final result = await compute(_processInIsolate, _IsolateInput(
      imageBytes: bytes,
      classifierReady: true,
    ));

    if (result == null) return null;

    // Classify each segmented tile (must happen on main thread for TFLite)
    final tileCodes = <String>[];
    final confidences = <double>[];

    for (final tileImage in result) {
      final classifications = _classifier.classify(tileImage, topK: 1);
      if (classifications.isEmpty) continue;
      tileCodes.add(classifications.first.tileCode);
      confidences.add(classifications.first.confidence);
    }

    if (tileCodes.length < 13) return null;

    final avgConf = confidences.isEmpty
        ? 0.0
        : confidences.reduce((a, b) => a + b) / confidences.length;

    if (avgConf < 0.3) return null;

    return OnDeviceRecognitionResult(
      tileCodes: tileCodes,
      confidences: confidences,
      avgConfidence: avgConf,
    );
  }

  void dispose() {
    _classifier.dispose();
    _ready = false;
  }
}

/// Input for isolate processing.
class _IsolateInput {
  final Uint8List imageBytes;
  final bool classifierReady;

  _IsolateInput({
    required List<int> imageBytes,
    required this.classifierReady,
  }) : imageBytes = imageBytes is Uint8List ? imageBytes : Uint8List.fromList(imageBytes);
}

/// Segment tiles in an isolate (CPU-bound image processing).
/// Returns list of cropped tile images, or null on failure.
List<img.Image>? _processInIsolate(_IsolateInput input) {
  final decoded = img.decodeImage(input.imageBytes);
  if (decoded == null) return null;

  final rgb = decoded.convert(numChannels: 3);
  final tiles = _segmentTiles(rgb);

  if (tiles.length < 13) return null;
  return tiles;
}

/// Segment individual tiles from the image using white-pixel connected
/// component analysis. Mirrors the server-side approach.
List<img.Image> _segmentTiles(img.Image image, {double tileAspect = 0.75}) {
  final w = image.width;
  final h = image.height;

  // Downscale for faster mask computation
  const scale = 4;
  final mW = w ~/ scale;
  final mH = h ~/ scale;
  if (mW <= 0 || mH <= 0) return [];

  // Build white-pixel mask (high value, low saturation in HSV-like check)
  final mask = Uint8List(mH * mW);
  for (int my = 0; my < mH; my++) {
    for (int mx = 0; mx < mW; mx++) {
      final px = image.getPixel(mx * scale, my * scale);
      final r = px.r.toInt();
      final g = px.g.toInt();
      final b = px.b.toInt();

      // Simple white detection: all channels high, low spread
      final maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
      final sat = maxC > 0 ? ((maxC - minC) * 255 ~/ maxC) : 0;

      if (maxC >= 160 && sat <= 80) {
        mask[my * mW + mx] = 1;
      }
    }
  }

  // Morphological cleanup (simple 3x3 close then open)
  _morphClose(mask, mW, mH);
  _morphOpen(mask, mW, mH);

  // Connected component labeling (8-connected flood fill)
  final labels = Int32List(mH * mW);
  int nextLabel = 0;
  // [minX, minY, maxX, maxY, pixelCount]
  final components = <List<int>>[];

  for (int y = 0; y < mH; y++) {
    for (int x = 0; x < mW; x++) {
      final idx = y * mW + x;
      if (mask[idx] != 1 || labels[idx] != 0) continue;

      nextLabel++;
      int minX = x, maxX = x, minY = y, maxY = y, count = 0;
      final stack = <int>[idx];
      labels[idx] = nextLabel;

      while (stack.isNotEmpty) {
        final ci = stack.removeLast();
        final cx = ci % mW;
        final cy = ci ~/ mW;
        count++;
        if (cx < minX) minX = cx;
        if (cx > maxX) maxX = cx;
        if (cy < minY) minY = cy;
        if (cy > maxY) maxY = cy;

        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dy == 0 && dx == 0) continue;
            final nx = cx + dx, ny = cy + dy;
            if (nx >= 0 && nx < mW && ny >= 0 && ny < mH) {
              final ni = ny * mW + nx;
              if (mask[ni] == 1 && labels[ni] == 0) {
                labels[ni] = nextLabel;
                stack.add(ni);
              }
            }
          }
        }
      }

      components.add([minX, minY, maxX, maxY, count]);
    }
  }

  if (components.isEmpty) return [];

  // Find largest component for relative size filtering
  int maxArea = 0;
  for (final c in components) {
    if (c[4] > maxArea) maxArea = c[4];
  }
  final areaThreshold = (maxArea * 0.15).toInt().clamp(20, maxArea);

  // Filter and subdivide
  final tileImages = <img.Image>[];

  for (final c in components) {
    final count = c[4];
    if (count < areaThreshold) continue;

    final bw = c[2] - c[0] + 1;
    final bh = c[3] - c[1] + 1;
    final bboxArea = bw * bh;
    if (bboxArea == 0 || count / bboxArea < 0.20) continue;

    // Convert back to original image coordinates
    final ox = c[0] * scale;
    final oy = c[1] * scale;
    final ow = bw * scale;
    final oh = bh * scale;

    if (ow >= oh) {
      final expectedTileW = oh * tileAspect;
      final nSub = expectedTileW > 0
          ? (ow / expectedTileW).round().clamp(1, 20)
          : 1;
      final subW = ow / nSub;
      for (int i = 0; i < nSub; i++) {
        final sx = ox + (i * subW).toInt();
        final ex = ox + ((i + 1) * subW).toInt();
        final cropped = img.copyCrop(image,
            x: sx.clamp(0, w - 1),
            y: oy.clamp(0, h - 1),
            width: (ex - sx).clamp(1, w - sx),
            height: oh.clamp(1, h - oy));
        tileImages.add(cropped);
      }
    } else {
      final expectedTileH = ow / tileAspect;
      final nSub = expectedTileH > 0
          ? (oh / expectedTileH).round().clamp(1, 20)
          : 1;
      final subH = oh / nSub;
      for (int i = 0; i < nSub; i++) {
        final sy = oy + (i * subH).toInt();
        final ey = oy + ((i + 1) * subH).toInt();
        final cropped = img.copyCrop(image,
            x: ox.clamp(0, w - 1),
            y: sy.clamp(0, h - 1),
            width: ow.clamp(1, w - ox),
            height: (ey - sy).clamp(1, h - sy));
        tileImages.add(cropped);
      }
    }
  }

  // Sort left-to-right (by x center), then top-to-bottom
  // Not needed here since components are already in scan order

  return tileImages;
}

// Simple 3x3 morphological close (dilate then erode)
void _morphClose(Uint8List mask, int w, int h) {
  final dilated = Uint8List(mask.length);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      bool found = false;
      for (int dy = -1; dy <= 1 && !found; dy++) {
        for (int dx = -1; dx <= 1 && !found; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 && nx < w && ny >= 0 && ny < h && mask[ny * w + nx] == 1) {
            found = true;
          }
        }
      }
      dilated[y * w + x] = found ? 1 : 0;
    }
  }
  // Erode
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      bool allSet = true;
      for (int dy = -1; dy <= 1 && allSet; dy++) {
        for (int dx = -1; dx <= 1 && allSet; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
            if (dilated[ny * w + nx] != 1) allSet = false;
          }
        }
      }
      mask[y * w + x] = allSet ? 1 : 0;
    }
  }
}

// Simple 3x3 morphological open (erode then dilate)
void _morphOpen(Uint8List mask, int w, int h) {
  final eroded = Uint8List(mask.length);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      bool allSet = true;
      for (int dy = -1; dy <= 1 && allSet; dy++) {
        for (int dx = -1; dx <= 1 && allSet; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
            if (mask[ny * w + nx] != 1) allSet = false;
          }
        }
      }
      eroded[y * w + x] = allSet ? 1 : 0;
    }
  }
  // Dilate
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      bool found = false;
      for (int dy = -1; dy <= 1 && !found; dy++) {
        for (int dx = -1; dx <= 1 && !found; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 && nx < w && ny >= 0 && ny < h && eroded[ny * w + nx] == 1) {
            found = true;
          }
        }
      }
      mask[y * w + x] = found ? 1 : 0;
    }
  }
}
