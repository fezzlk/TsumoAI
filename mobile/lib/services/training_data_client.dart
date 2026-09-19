import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import '../config.dart';
import 'auth_service.dart';

/// Result of a batch upload: how many tiles made it, and their server-side
/// entry ids (for a later [TrainingDataClient.deleteEntries] undo).
class TrainingUploadResult {
  final int uploadedCount;
  final List<String> entryIds;

  const TrainingUploadResult({
    required this.uploadedCount,
    required this.entryIds,
  });
}

/// Client for uploading training data to the backend.
class TrainingDataClient {
  late final Dio _dio;

  TrainingDataClient() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
  }

  String get _baseUrl => AppConfig.apiBaseUrl;

  /// Upload a single tile image with its correct label.
  Future<Map<String, dynamic>> uploadTile({
    required img.Image tileImage,
    required String tileCode,
    String? predictedTileCode,
    double? predictedConfidence,
    String? recognitionModelVersion,
    String? recognitionModelSource,
    String? preprocessingVersion,
    String source = 'user',
  }) async {
    final token = await AuthService.idToken(interactive: true);
    final jpegBytes = Uint8List.fromList(img.encodeJpg(tileImage, quality: 90));

    final formData = FormData.fromMap({
      'image': MultipartFile.fromBytes(jpegBytes, filename: 'tile.jpg'),
      'tile_code': tileCode,
      'predicted_tile_code': ?predictedTileCode,
      'predicted_confidence': ?predictedConfidence,
      'recognition_model_version': ?recognitionModelVersion,
      'recognition_model_source': ?recognitionModelSource,
      'preprocessing_version': ?preprocessingVersion,
      'source': source,
    });

    final response = await _dio.post(
      '$_baseUrl/api/v1/training-data/upload',
      data: formData,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    return response.data as Map<String, dynamic>;
  }

  /// Upload multiple tiles at once (14-tile batch). Keeps going after a
  /// per-tile failure (one bad tile shouldn't block the rest), but — unlike
  /// silently discarding every error — surfaces the *first* failure by
  /// throwing it once all tiles have been attempted and at least one
  /// failed, so the caller/UI can show what actually went wrong instead of
  /// just an opaque "0 uploaded".
  // Up to 18 tiles (kan hands), each its own HTTP round-trip: run them
  // concurrently rather than one at a time. Network latency, not the
  // per-request work, dominates the time either way takes, so this cuts
  // total wall-clock roughly by however many requests fit in flight at
  // once, instead of multiplying one request's latency by the tile count.
  Future<TrainingUploadResult> uploadBatch({
    required List<img.Image> images,
    required List<String> tileCodes,
    required List<String> predictedTileCodes,
    List<double?> predictedConfidences = const [],
    String? recognitionModelVersion,
    String? recognitionModelSource,
    String? preprocessingVersion,
    String source = 'user',
  }) async {
    final count = images.length < tileCodes.length
        ? images.length
        : tileCodes.length;
    final results = await Future.wait(
      List.generate(count, (i) async {
        try {
          final response = await uploadTile(
            tileImage: images[i],
            tileCode: tileCodes[i],
            predictedTileCode: i < predictedTileCodes.length
                ? predictedTileCodes[i]
                : null,
            predictedConfidence: i < predictedConfidences.length
                ? predictedConfidences[i]
                : null,
            recognitionModelVersion: recognitionModelVersion,
            recognitionModelSource: recognitionModelSource,
            preprocessingVersion: preprocessingVersion,
            source: source,
          );
          return (id: response['id'] as String, error: null as Object?);
        } catch (e) {
          return (id: null as String?, error: e);
        }
      }),
    );
    final entryIds = [
      for (final r in results)
        if (r.id != null) r.id!,
    ];
    final firstError = results.firstWhere(
      (r) => r.error != null,
      orElse: () => (id: null, error: null),
    ).error;
    if (entryIds.isEmpty && firstError != null) {
      throw firstError;
    }
    return TrainingUploadResult(
      uploadedCount: entryIds.length,
      entryIds: entryIds,
    );
  }

  /// Undo a previous [uploadBatch] by deleting the uploaded entries. The
  /// server-side delete endpoint is admin-only, so this will throw (with the
  /// server's 403) if the signed-in account isn't an admin. Concurrent for
  /// the same reason as [uploadBatch].
  Future<int> deleteEntries(List<String> ids) async {
    final token = await AuthService.idToken(interactive: true);
    final results = await Future.wait(
      ids.map((id) async {
        try {
          await _dio.delete(
            '$_baseUrl/api/v1/training-data/$id',
            options: Options(headers: {'Authorization': 'Bearer $token'}),
          );
          return null;
        } catch (e) {
          return e;
        }
      }),
    );
    final deleted = results.where((e) => e == null).length;
    final firstError = results.firstWhere(
      (e) => e != null,
      orElse: () => null,
    );
    if (deleted == 0 && firstError != null) {
      throw firstError;
    }
    return deleted;
  }
}
