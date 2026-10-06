import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'model_updater.dart';

/// On-device mahjong tile classifier using TFLite (MobileNetV2).
///
/// Includes preprocessing to handle real-world camera crops:
/// 1. Replace green mat background with white
/// 2. Detect and crop to tile face region
/// 3. Apply contrast normalization
class ClassifierRuntime {
  static const String _bundledModelPath = 'assets/ml/tile_classifier.tflite';
  static const String _bundledLabelsPath = 'assets/ml/labels.txt';
  static const String _bundledModelVersion = 'bundled-ed2678e9c4f0';
  static const int _inputSize = 224;

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isReady = false;
  String _modelSource = 'bundled';
  String _modelVersion = _bundledModelVersion;

  bool get isReady => _isReady;
  List<String> get labels => _labels;
  String get modelSource => _modelSource;
  String get modelVersion => _modelVersion;

  Future<void> init() async {
    // Try to use a downloaded (newer) model first
    final updatedDir = await ModelUpdater.checkAndUpdate();

    if (updatedDir != null) {
      final modelFile = File('$updatedDir/tile_classifier.tflite');
      final labelsFile = File('$updatedDir/labels.txt');
      if (modelFile.existsSync() && labelsFile.existsSync()) {
        try {
          _interpreter = Interpreter.fromFile(modelFile);
          _labels = labelsFile
              .readAsStringSync()
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          _isReady = true;
          _modelSource = 'downloaded';
          _modelVersion = _readDownloadedModelVersion(updatedDir);
          debugPrint('TileClassifier: using downloaded model from $updatedDir');
          return;
        } catch (e) {
          debugPrint(
            'TileClassifier: downloaded model failed, falling back to bundled: $e',
          );
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
      _labels = labelsData
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      _isReady = false;
      throw Exception('ラベル読込失敗 ($_bundledLabelsPath): $e');
    }

    _isReady = true;
    _modelSource = 'bundled';
    _modelVersion = _bundledModelVersion;
  }

  static String _readDownloadedModelVersion(String modelDir) {
    try {
      final decoded = jsonDecode(
        File('$modelDir/model_meta.json').readAsStringSync(),
      );
      if (decoded is Map<String, dynamic>) {
        final version = decoded['version'];
        if (version is String && version.trim().isNotEmpty) {
          return version.trim();
        }
      }
    } catch (e) {
      debugPrint('TileClassifier: model version metadata unavailable: $e');
    }
    return 'downloaded-unknown';
  }

  Future<List<double>> run(Float32List input, int labelCount) async {
    final output = List.filled(labelCount, 0.0).reshape([1, labelCount]);
    _interpreter!.run(input.reshape([1, _inputSize, _inputSize, 3]), output);
    return List<double>.from(output[0] as List);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isReady = false;
  }
}
