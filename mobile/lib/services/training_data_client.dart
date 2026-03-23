import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import '../config.dart';

/// Client for uploading training data to the backend.
class TrainingDataClient {
  late final Dio _dio;

  TrainingDataClient() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  String get _baseUrl => AppConfig.apiBaseUrl;

  /// Upload a single tile image with its correct label.
  Future<Map<String, dynamic>> uploadTile({
    required img.Image tileImage,
    required String tileCode,
    String source = 'user',
  }) async {
    final jpegBytes = Uint8List.fromList(img.encodeJpg(tileImage, quality: 90));

    final formData = FormData.fromMap({
      'image': MultipartFile.fromBytes(jpegBytes, filename: 'tile.jpg'),
      'tile_code': tileCode,
      'source': source,
    });

    final response = await _dio.post(
      '$_baseUrl/api/v1/training-data/upload',
      data: formData,
    );

    return response.data as Map<String, dynamic>;
  }

  /// Upload multiple tiles at once (14-tile batch).
  Future<int> uploadBatch({
    required List<img.Image> images,
    required List<String> tileCodes,
    String source = 'user',
  }) async {
    int uploaded = 0;
    for (int i = 0; i < images.length && i < tileCodes.length; i++) {
      try {
        await uploadTile(
          tileImage: images[i],
          tileCode: tileCodes[i],
          source: source,
        );
        uploaded++;
      } catch (e) {
        // Continue with remaining tiles
      }
    }
    return uploaded;
  }
}
