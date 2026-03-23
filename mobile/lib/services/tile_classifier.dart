import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

/// On-device mahjong tile classifier using TFLite (MobileNetV2).
///
/// Includes preprocessing to handle real-world camera crops:
/// 1. Replace green mat background with white
/// 2. Detect and crop to tile face region
/// 3. Apply contrast normalization
class TileClassifier {
  static const String _modelPath = 'assets/ml/tile_classifier.tflite';
  static const String _labelsPath = 'assets/ml/labels.txt';
  static const int _inputSize = 224;

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isReady = false;

  bool get isReady => _isReady;
  List<String> get labels => _labels;

  Future<void> init() async {
    try {
      final modelBytes = await rootBundle.load(_modelPath);
      final tempDir = await getTemporaryDirectory();
      final modelFile = File('${tempDir.path}/tile_classifier.tflite');
      await modelFile.writeAsBytes(modelBytes.buffer.asUint8List());
      _interpreter = Interpreter.fromFile(modelFile);
    } catch (e) {
      _isReady = false;
      throw Exception('TFLiteモデル読込失敗 ($_modelPath): $e');
    }

    try {
      final labelsData = await rootBundle.loadString(_labelsPath);
      _labels = labelsData.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } catch (e) {
      _isReady = false;
      throw Exception('ラベル読込失敗 ($_labelsPath): $e');
    }

    _isReady = true;
  }

  /// Classify a cropped tile image with preprocessing pipeline.
  List<TileClassification> classify(img.Image tileImage, {int topK = 3}) {
    if (!_isReady || _interpreter == null) return [];

    // Preprocessing pipeline
    var processed = _preprocessTile(tileImage);

    // Resize to model input
    final resized = img.copyResize(processed, width: _inputSize, height: _inputSize);

    // Convert to float32 tensor [-1, 1]
    final input = Float32List(_inputSize * _inputSize * 3);
    int idx = 0;
    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        input[idx++] = (pixel.r.toDouble() / 127.5) - 1.0;
        input[idx++] = (pixel.g.toDouble() / 127.5) - 1.0;
        input[idx++] = (pixel.b.toDouble() / 127.5) - 1.0;
      }
    }

    final inputTensor = input.reshape([1, _inputSize, _inputSize, 3]);
    final outputTensor = List.filled(_labels.length, 0.0).reshape([1, _labels.length]);

    _interpreter!.run(inputTensor, outputTensor);

    final scores = (outputTensor[0] as List<double>);
    final results = <TileClassification>[];
    for (int i = 0; i < scores.length; i++) {
      results.add(TileClassification(
        label: _labels[i],
        tileCode: _labelToTileCode(_labels[i]),
        confidence: scores[i],
      ));
    }
    results.sort((a, b) => b.confidence.compareTo(a.confidence));
    return results.take(topK).toList();
  }

  /// Preprocess a camera crop to look more like training data.
  ///
  /// 1. Replace green pixels with white (remove mat background)
  /// 2. Find the tile face (largest white/bright region)
  /// 3. Crop to tile face with small padding
  /// 4. Normalize contrast
  img.Image _preprocessTile(img.Image src) {
    final w = src.width;
    final h = src.height;

    // Step 1: Replace green background with white
    final cleaned = img.Image.from(src);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = cleaned.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();

        // Detect green: G is dominant, G > R+20, G > B+20
        if (g > r + 20 && g > b + 20 && g > 60) {
          cleaned.setPixelRgb(x, y, 240, 240, 240); // light gray (near white)
        }
      }
    }

    // Step 2: Find tile face bounding box (bright region)
    // Create brightness mask
    int minX = w, minY = h, maxX = 0, maxY = 0;
    bool found = false;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = cleaned.getPixel(x, y);
        final brightness = (p.r.toInt() + p.g.toInt() + p.b.toInt()) ~/ 3;
        if (brightness > 150) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
          found = true;
        }
      }
    }

    if (!found || maxX <= minX || maxY <= minY) {
      return cleaned;
    }

    // Step 3: Crop to tile face with 5% padding
    final cropW = maxX - minX;
    final cropH = maxY - minY;
    final padX = (cropW * 0.05).round();
    final padY = (cropH * 0.05).round();
    final cx = math.max(0, minX - padX);
    final cy = math.max(0, minY - padY);
    final cw = math.min(w - cx, cropW + padX * 2);
    final ch = math.min(h - cy, cropH + padY * 2);

    if (cw < 10 || ch < 10) return cleaned;

    var cropped = img.copyCrop(cleaned, x: cx, y: cy, width: cw, height: ch);

    // Step 4: Auto-contrast normalization
    cropped = img.normalize(cropped, min: 0, max: 255);

    return cropped;
  }

  static String _labelToTileCode(String label) {
    if (label.startsWith('dots-')) return '${label.substring(5)}p';
    if (label.startsWith('bamboo-')) return '${label.substring(7)}s';
    if (label.startsWith('characters-')) return '${label.substring(11)}m';
    const honorsMap = {
      'honors-east': 'E', 'honors-south': 'S', 'honors-west': 'W', 'honors-north': 'N',
      'honors-red': 'C', 'honors-green': 'F', 'honors-white': 'P',
    };
    return honorsMap[label] ?? label;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isReady = false;
  }
}

class TileClassification {
  final String label;
  final String tileCode;
  final double confidence;

  const TileClassification({required this.label, required this.tileCode, required this.confidence});

  @override
  String toString() => '$tileCode (${(confidence * 100).toStringAsFixed(1)}%)';
}
