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
  static const String _activeFileName = 'active_model';

  /// Check for updates and download if a newer version is available.
  /// Returns a complete local model cache, including when the update check
  /// fails, or null when the caller should use the bundled model.
  static Future<String?> checkAndUpdate({
    http.Client? client,
    Directory? supportDirectory,
  }) async {
    final updateClient = client ?? http.Client();
    Directory? modelDir;
    Directory? candidateDir;
    try {
      final appDir = supportDirectory ?? await getApplicationSupportDirectory();
      modelDir = Directory('${appDir.path}/ml_model');
      await modelDir.create(recursive: true);

      // Get current local version
      final cachedModelPath = _existingModelPath(modelDir);
      final localMetaFile = File(
        '${cachedModelPath ?? modelDir.path}/$_metaFileName',
      );
      String? localVersion;
      if (localMetaFile.existsSync()) {
        final meta = json.decode(localMetaFile.readAsStringSync());
        localVersion = meta['version'] as String?;
      }

      // Check latest version from API
      final baseUrl = AppConfig.apiBaseUrl;
      final res = await updateClient
          .get(Uri.parse('$baseUrl/api/v1/model/latest'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return _existingModelPath(modelDir);

      final latest = json.decode(res.body);
      if (latest['status'] != 'ok') return _existingModelPath(modelDir);

      final remoteVersion = latest['version'] as String;
      if (remoteVersion == localVersion && cachedModelPath != null) {
        debugPrint('ModelUpdater: model is up to date ($localVersion)');
        return cachedModelPath;
      }

      debugPrint(
        'ModelUpdater: new model available $localVersion -> $remoteVersion, downloading...',
      );

      // Download new model
      final modelUrl = '$baseUrl/api/v1/model/download/tile_classifier.tflite';
      final modelRes = await updateClient
          .get(Uri.parse(modelUrl))
          .timeout(const Duration(seconds: 120));
      if (modelRes.statusCode != 200 || modelRes.bodyBytes.isEmpty) {
        return _existingModelPath(modelDir);
      }

      final labelsUrl = '$baseUrl/api/v1/model/download/labels.txt';
      final labelsRes = await updateClient
          .get(Uri.parse(labelsUrl))
          .timeout(const Duration(seconds: 30));
      if (labelsRes.statusCode != 200 || labelsRes.body.trim().isEmpty) {
        return _existingModelPath(modelDir);
      }

      // Complete a new, immutable pair before publishing it. An interrupted
      // write must never replace only one file in the currently active cache.
      candidateDir = await modelDir.createTemp('candidate_');
      await File(
        '${candidateDir.path}/$_modelFileName',
      ).writeAsBytes(modelRes.bodyBytes, flush: true);
      await File(
        '${candidateDir.path}/$_labelsFileName',
      ).writeAsString(labelsRes.body, flush: true);
      await File(
        '${candidateDir.path}/$_metaFileName',
      ).writeAsString(json.encode(latest), flush: true);

      // Rename a completed pointer on the same filesystem, so readers see
      // either the old complete cache or the new one. Existing cache files
      // stay available to classifiers which have already selected their path.
      final candidateName = candidateDir.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
      final pointer = File('${candidateDir.path}/$_activeFileName');
      await pointer.writeAsString(candidateName, flush: true);
      await pointer.rename('${modelDir.path}/$_activeFileName');
      final publishedPath = candidateDir.path;
      candidateDir = null;

      debugPrint('ModelUpdater: downloaded model $remoteVersion');
      return publishedPath;
    } catch (e) {
      debugPrint('ModelUpdater: check failed: $e');
      return _existingModelPath(modelDir);
    } finally {
      if (candidateDir != null) {
        try {
          await candidateDir.delete(recursive: true);
        } on FileSystemException catch (e) {
          debugPrint('ModelUpdater: candidate cleanup failed: $e');
        }
      }
      if (client == null) updateClient.close();
    }
  }

  static String? _existingModelPath(Directory? modelDir) {
    if (modelDir == null) return null;
    try {
      final pointer = File('${modelDir.path}/$_activeFileName');
      if (pointer.existsSync()) {
        final name = pointer.readAsStringSync().trim();
        // The pointer is a single generated directory name, never a path
        // supplied by the model server or an absolute filesystem location.
        if (RegExp(r'^candidate_[A-Za-z0-9_-]+$').hasMatch(name)) {
          final activePath = _completeModelPath(
            Directory('${modelDir.path}/$name'),
          );
          if (activePath != null) return activePath;
        }
      }
    } on FileSystemException {
      // Fall back to a cache written by versions before atomic publication.
    } on FormatException {
      // A damaged pointer must not prevent the legacy/bundled fallback.
    }
    return _completeModelPath(modelDir);
  }

  static String? _completeModelPath(Directory modelDir) {
    try {
      final model = File('${modelDir.path}/$_modelFileName');
      final labels = File('${modelDir.path}/$_labelsFileName');
      return model.existsSync() &&
              model.lengthSync() > 0 &&
              labels.existsSync() &&
              labels.readAsStringSync().trim().isNotEmpty
          ? modelDir.path
          : null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }
}
