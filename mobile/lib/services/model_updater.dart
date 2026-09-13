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
  /// no cached or bundled model is usable.
  ///
  /// [client] and [modelDir] are injectable for testing; production
  /// callers should omit both and let them resolve to the real HTTP
  /// client and the app's support directory.
  static Future<String?> checkAndUpdate({http.Client? client, Directory? modelDir}) async {
    final dir = modelDir ?? await _defaultModelDir();
    await dir.create(recursive: true);

    // Get current local version
    final localMetaFile = File('${dir.path}/$_metaFileName');
    String? localVersion;
    if (localMetaFile.existsSync()) {
      final meta = json.decode(localMetaFile.readAsStringSync());
      localVersion = meta['version'] as String?;
    }

    final httpClient = client ?? http.Client();
    try {
      // Check latest version from API
      final baseUrl = AppConfig.apiBaseUrl;
      final res = await httpClient.get(Uri.parse('$baseUrl/api/v1/model/latest'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return _existingModelPath(dir);

      final latest = json.decode(res.body);
      if (latest['status'] != 'ok') return _existingModelPath(dir);

      final remoteVersion = latest['version'] as String;
      if (remoteVersion == localVersion) {
        debugPrint('ModelUpdater: model is up to date ($localVersion)');
        return dir.path;
      }

      debugPrint('ModelUpdater: new model available $localVersion -> $remoteVersion, downloading...');

      // Download new model
      final modelUrl = '$baseUrl/api/v1/model/download/tile_classifier.tflite';
      final modelRes = await httpClient.get(Uri.parse(modelUrl))
          .timeout(const Duration(seconds: 120));
      if (modelRes.statusCode != 200) return _existingModelPath(dir);

      final labelsUrl = '$baseUrl/api/v1/model/download/labels.txt';
      final labelsRes = await httpClient.get(Uri.parse(labelsUrl))
          .timeout(const Duration(seconds: 30));
      if (labelsRes.statusCode != 200) return _existingModelPath(dir);

      // Write files
      await File('${dir.path}/$_modelFileName').writeAsBytes(modelRes.bodyBytes);
      await File('${dir.path}/$_labelsFileName').writeAsString(labelsRes.body);
      await localMetaFile.writeAsString(json.encode(latest));

      debugPrint('ModelUpdater: downloaded model $remoteVersion');
      return dir.path;
    } catch (e) {
      // Network/parse failures (e.g. DNS resolution failure while offline,
      // request timeout) must not discard an already-downloaded model.
      debugPrint('ModelUpdater: check failed: $e');
      return _existingModelPath(dir);
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static Future<Directory> _defaultModelDir() async {
    final appDir = await getApplicationSupportDirectory();
    return Directory('${appDir.path}/ml_model');
  }

  static String? _existingModelPath(Directory modelDir) {
    final f = File('${modelDir.path}/$_modelFileName');
    return f.existsSync() ? modelDir.path : null;
  }
}
