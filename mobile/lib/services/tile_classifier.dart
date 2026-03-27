import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'model_updater.dart';

/// On-device mahjong tile classifier using TFLite (MobileNetV2).
///
/// Includes preprocessing to handle real-world camera crops:
/// 1. Replace green mat background with white
/// 2. Detect and crop to tile face region
/// 3. Apply contrast normalization
class TileClassifier {
  static const String _bundledModelPath = 'assets/ml/tile_classifier.tflite';
  static const String _bundledLabelsPath = 'assets/ml/labels.txt';
  static const int _inputSize = 224;

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isReady = false;
  String _modelSource = 'bundled';

  bool get isReady => _isReady;
  List<String> get labels => _labels;
  String get modelSource => _modelSource;

  Future<void> init() async {
    // Try to use a downloaded (newer) model first
    final updatedDir = await ModelUpdater.checkAndUpdate();

    if (updatedDir != null) {
      final modelFile = File('$updatedDir/tile_classifier.tflite');
      final labelsFile = File('$updatedDir/labels.txt');
      if (modelFile.existsSync() && labelsFile.existsSync()) {
        try {
          _interpreter = Interpreter.fromFile(modelFile);
          _labels = labelsFile.readAsStringSync()
              .split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          _isReady = true;
          _modelSource = 'downloaded';
          debugPrint('TileClassifier: using downloaded model from $updatedDir');
          return;
        } catch (e) {
          debugPrint('TileClassifier: downloaded model failed, falling back to bundled: $e');
        }
      }
    }

    // Fallback: bundled model
    try {
      final modelBytes = await rootBundle.load(_bundledModelPath);
      final tempDir = await getTemporaryDirectory();
      final modelFile = File('${tempDir.path}/tile_classifier.tflite');
      await modelFile.writeAsBytes(modelBytes.buffer.asUint8List());
      _interpreter = Interpreter.fromFile(modelFile);
    } catch (e) {
      _isReady = false;
      throw Exception('TFLiteモデル読込失敗 ($_bundledModelPath): $e');
    }

    try {
      final labelsData = await rootBundle.loadString(_bundledLabelsPath);
      _labels = labelsData.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } catch (e) {
      _isReady = false;
      throw Exception('ラベル読込失敗 ($_bundledLabelsPath): $e');
    }

    _isReady = true;
    _modelSource = 'bundled';
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
  /// 1. Edge detection (Sobel) to find tile face boundaries
  /// 2. Crop to the detected tile face
  /// 3. Replace green background with white
  /// 4. Normalize contrast
  img.Image _preprocessTile(img.Image src) {
    final w = src.width;
    final h = src.height;
    if (w < 10 || h < 10) return src;

    // Step 1: Edge detection to find tile face boundaries
    final gray = img.grayscale(img.Image.from(src));
    final edges = img.sobel(gray);

    // Step 2: Horizontal projection (find top/bottom of tile face)
    // Sum edge intensity per row
    final hProj = List.filled(h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        hProj[y] += edges.getPixel(x, y).r.toInt();
      }
    }
    // Vertical projection (find left/right of tile face)
    final vProj = List.filled(w, 0);
    for (int x = 0; x < w; x++) {
      for (int y = 0; y < h; y++) {
        vProj[x] += edges.getPixel(x, y).r.toInt();
      }
    }

    // Find bounds using edge concentration
    int hPeak = 0, vPeak = 0;
    for (final v in hProj) { if (v > hPeak) hPeak = v; }
    for (final v in vProj) { if (v > vPeak) vPeak = v; }

    final hThreshold = hPeak * 0.25;
    final vThreshold = vPeak * 0.25;

    int top = 0, bottom = h - 1, left = 0, right = w - 1;

    // Find top edge (first row with significant edges)
    for (int y = 0; y < h; y++) {
      if (hProj[y] > hThreshold) { top = y; break; }
    }
    // Find bottom edge (last row with significant edges)
    for (int y = h - 1; y >= 0; y--) {
      if (hProj[y] > hThreshold) { bottom = y; break; }
    }
    // Find left edge
    for (int x = 0; x < w; x++) {
      if (vProj[x] > vThreshold) { left = x; break; }
    }
    // Find right edge
    for (int x = w - 1; x >= 0; x--) {
      if (vProj[x] > vThreshold) { right = x; break; }
    }

    // Validate bounds
    if (right <= left + 5 || bottom <= top + 5) {
      // Edge detection failed, use center crop
      final margin = (w * 0.1).round();
      left = margin;
      right = w - margin;
      top = (h * 0.05).round();
      bottom = h - (h * 0.05).round();
    }

    // Add small padding inside
    final padX = ((right - left) * 0.03).round();
    final padY = ((bottom - top) * 0.03).round();
    left = math.max(0, left + padX);
    right = math.min(w - 1, right - padX);
    top = math.max(0, top + padY);
    bottom = math.min(h - 1, bottom - padY);

    // Step 3: Crop to tile face
    final cw = right - left;
    final ch = bottom - top;
    if (cw < 5 || ch < 5) return src;

    var cropped = img.copyCrop(src, x: left, y: top, width: cw, height: ch);

    // Step 4: Replace green pixels with white
    for (int y = 0; y < cropped.height; y++) {
      for (int x = 0; x < cropped.width; x++) {
        final p = cropped.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        if (g > r + 15 && g > b + 15 && g > 50) {
          cropped.setPixelRgb(x, y, 245, 245, 245);
        }
      }
    }

    // Step 5: Auto-contrast
    cropped = img.normalize(cropped, min: 0, max: 255);

    return cropped;
  }

  static String _labelToTileCode(String label) {
    if (label.startsWith('dots-')) return '${label.substring(5)}p';
    if (label.startsWith('bamboo-')) return '${label.substring(7)}s';
    if (label.startsWith('characters-')) return '${label.substring(11)}m';
    const map = {
      'honors-east': 'E', 'honors-south': 'S', 'honors-west': 'W', 'honors-north': 'N',
      'honors-red': 'C', 'honors-green': 'F', 'honors-white': 'P',
      // Bonus tiles → not used in Japanese mahjong, map to short codes
      'bonus-spring': '春', 'bonus-summer': '夏', 'bonus-autumn': '秋', 'bonus-winter': '冬',
      'bonus-plum': '梅', 'bonus-orchid': '蘭', 'bonus-chrysanthemum': '菊', 'bonus-bamboo': '竹',
    };
    return map[label] ?? label;
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
