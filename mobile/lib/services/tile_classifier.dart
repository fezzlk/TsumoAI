import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

/// On-device mahjong tile classifier using TFLite (MobileNetV2).
///
/// Given a cropped tile image, returns the predicted tile class name
/// and confidence score.
class TileClassifier {
  static const String _modelPath = 'assets/ml/tile_classifier.tflite';
  static const String _labelsPath = 'assets/ml/labels.txt';
  static const int _inputSize = 224;

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isReady = false;

  bool get isReady => _isReady;
  List<String> get labels => _labels;

  /// Load model and labels. Call once at app startup.
  Future<void> init() async {
    try {
      // Copy asset to temp file — tflite_flutter needs a file path
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
      _labels = labelsData
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      _isReady = false;
      throw Exception('ラベル読込失敗 ($_labelsPath): $e');
    }

    _isReady = true;
  }

  /// Classify a cropped tile image (as raw RGBA/RGB bytes from image package).
  ///
  /// Returns a list of (label, confidence) sorted by confidence descending.
  List<TileClassification> classify(img.Image tileImage, {int topK = 3}) {
    if (!_isReady || _interpreter == null) {
      return [];
    }

    // Resize to model input size
    final resized = img.copyResize(tileImage, width: _inputSize, height: _inputSize);

    // Convert to float32 tensor with MobileNetV2 preprocessing ([-1, 1])
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

    // Reshape to [1, 224, 224, 3]
    final inputTensor = input.reshape([1, _inputSize, _inputSize, 3]);
    final outputTensor = List.filled(_labels.length, 0.0).reshape([1, _labels.length]);

    _interpreter!.run(inputTensor, outputTensor);

    final scores = (outputTensor[0] as List<double>);

    // Build results sorted by confidence
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

  /// Convert dataset label name to mahjong tile code used by the backend.
  /// e.g. "dots-1" → "1p", "bamboo-3" → "3s", "characters-7" → "7m",
  ///      "honors-east" → "E", "honors-red" → "C"
  static String _labelToTileCode(String label) {
    // Dots → pinzu (p)
    if (label.startsWith('dots-')) {
      return '${label.substring(5)}p';
    }
    // Bamboo → souzu (s)
    if (label.startsWith('bamboo-')) {
      return '${label.substring(7)}s';
    }
    // Characters → manzu (m)
    if (label.startsWith('characters-')) {
      return '${label.substring(11)}m';
    }
    // Honors
    const honorsMap = {
      'honors-east': 'E',
      'honors-south': 'S',
      'honors-west': 'W',
      'honors-north': 'N',
      'honors-red': 'C',    // 中 (Chun)
      'honors-green': 'F',  // 發 (Hatsu)
      'honors-white': 'P',  // 白 (Haku/Pai)
    };
    if (honorsMap.containsKey(label)) {
      return honorsMap[label]!;
    }
    // Bonus tiles (not used in Japanese mahjong, return label as-is)
    return label;
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

  const TileClassification({
    required this.label,
    required this.tileCode,
    required this.confidence,
  });

  @override
  String toString() => '$tileCode (${(confidence * 100).toStringAsFixed(1)}%)';
}
