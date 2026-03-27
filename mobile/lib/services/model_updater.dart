import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config.dart';

/// Checks GCS for a newer model and downloads it if available.
/// The model is stored locally and used by TileClassifier.
class ModelUpdater {
  static const String _modelFileName = 'tile_classifier.tflite';
  static const String _labelsFileName = 'labels.txt';
  static const String _metaFileName = 'model_meta.json';

  /// Check for updates and download if a newer version is available.
  /// Returns the local directory containing the model, or null if
  /// no update is available (use bundled model).
  static Future<String?> checkAndUpdate() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final modelDir = Directory('${appDir.path}/ml_model');
      await modelDir.create(recursive: true);

      // Get current local version
      final localMetaFile = File('${modelDir.path}/$_metaFileName');
      String? localVersion;
      if (localMetaFile.existsSync()) {
        final meta = json.decode(localMetaFile.readAsStringSync());
        localVersion = meta['version'] as String?;
      }

      // Check latest version from API
      final baseUrl = AppConfig.apiBaseUrl;
      final res = await http.get(Uri.parse('$baseUrl/api/v1/model/latest'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return _existingModelPath(modelDir);

      final latest = json.decode(res.body);
      if (latest['status'] != 'ok') return _existingModelPath(modelDir);

      final remoteVersion = latest['version'] as String;
      if (remoteVersion == localVersion) {
        debugPrint('ModelUpdater: model is up to date ($localVersion)');
        return modelDir.path;
      }

      debugPrint('ModelUpdater: new model available $localVersion -> $remoteVersion, downloading...');

      // Download new model
      final modelUrl = '$baseUrl/api/v1/model/download/tile_classifier.tflite';
      final modelRes = await http.get(Uri.parse(modelUrl))
          .timeout(const Duration(seconds: 120));
      if (modelRes.statusCode != 200) return _existingModelPath(modelDir);

      final labelsUrl = '$baseUrl/api/v1/model/download/labels.txt';
      final labelsRes = await http.get(Uri.parse(labelsUrl))
          .timeout(const Duration(seconds: 30));
      if (labelsRes.statusCode != 200) return _existingModelPath(modelDir);

      // Write files
      await File('${modelDir.path}/$_modelFileName').writeAsBytes(modelRes.bodyBytes);
      await File('${modelDir.path}/$_labelsFileName').writeAsString(labelsRes.body);
      await localMetaFile.writeAsString(json.encode(latest));

      debugPrint('ModelUpdater: downloaded model $remoteVersion');
      return modelDir.path;
    } catch (e) {
      debugPrint('ModelUpdater: check failed: $e');
      return null;
    }
  }

  static String? _existingModelPath(Directory modelDir) {
    final f = File('${modelDir.path}/$_modelFileName');
    return f.existsSync() ? modelDir.path : null;
  }
}
