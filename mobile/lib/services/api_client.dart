import 'dart:io';
import 'package:dio/dio.dart';
import '../config.dart';
import '../models/recognize_result.dart';
import '../models/score_request.dart';
import '../models/score_result.dart';

class ApiClient {
  late final Dio _dio;

  ApiClient() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 60),
    ));
  }

  String get _baseUrl => AppConfig.apiBaseUrl;

  /// Upload image and recognize tiles (synchronous call, no polling needed)
  Future<RecognizeResponse> recognize(File imageFile) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        imageFile.path,
        filename: 'hand.jpg',
      ),
    });

    final response = await _dio.post(
      '$_baseUrl/api/v1/recognize',
      data: formData,
    );

    return RecognizeResponse.fromJson(response.data);
  }

  /// Calculate score from hand data.
  /// Returns null if the hand is not a valid winning shape (422).
  /// Throws on other errors.
  Future<ScoreResponse?> calculateScore(ScoreRequest request) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/api/v1/score',
        data: request.toJson(),
      );
      return ScoreResponse.fromJson(response.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        // Not a valid winning hand
        return null;
      }
      rethrow;
    }
  }

  /// Send recognition feedback with corrected tiles.
  Future<void> sendRecognitionFeedback({
    required Map<String, dynamic> recognitionResponse,
    required List<String> correctedTiles,
    String comment = '',
  }) async {
    await _dio.post(
      '$_baseUrl/api/v1/recognition/feedback',
      data: {
        'recognition_response': recognitionResponse,
        'corrected_tiles': correctedTiles,
        'comment': comment,
      },
    );
  }
}
