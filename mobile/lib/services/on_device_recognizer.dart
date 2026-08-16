import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'tile_classifier.dart';
import 'tile_segmenter.dart';

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

  final rgb = img.bakeOrientation(decoded).convert(numChannels: 3);
  final boxes = segmentTiles(rgb);
  if (boxes.length < 13) return null;

  final w = rgb.width, h = rgb.height;
  final tiles = <img.Image>[];
  for (final box in boxes) {
    final x = box.left.round().clamp(0, w - 1);
    final y = box.top.round().clamp(0, h - 1);
    final cw = box.width.round().clamp(1, w - x);
    final ch = box.height.round().clamp(1, h - y);
    tiles.add(img.copyCrop(rgb, x: x, y: y, width: cw, height: ch));
  }
  return tiles;
}
