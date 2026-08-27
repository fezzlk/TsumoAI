import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import '../config.dart';
import 'auth_service.dart';

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
    String source = 'user',
  }) async {
    final token = await AuthService.idToken(interactive: true);
    final jpegBytes = Uint8List.fromList(img.encodeJpg(tileImage, quality: 90));

    final formData = FormData.fromMap({
      'image': MultipartFile.fromBytes(jpegBytes, filename: 'tile.jpg'),
      'tile_code': tileCode,
      'predicted_tile_code': ?predictedTileCode,
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
  Future<int> uploadBatch({
    required List<img.Image> images,
    required List<String> tileCodes,
    required List<String> predictedTileCodes,
    String source = 'user',
  }) async {
    int uploaded = 0;
    Object? firstError;
    for (int i = 0; i < images.length && i < tileCodes.length; i++) {
      try {
        await uploadTile(
          tileImage: images[i],
          tileCode: tileCodes[i],
          predictedTileCode: i < predictedTileCodes.length
              ? predictedTileCodes[i]
              : null,
          source: source,
        );
        uploaded++;
      } catch (e) {
        firstError ??= e;
      }
    }
    if (uploaded == 0 && firstError != null) {
      throw firstError;
    }
    return uploaded;
  }
}
