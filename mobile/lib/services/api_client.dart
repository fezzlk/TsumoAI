import 'dart:io';
import 'dart:async';
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
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  String get _baseUrl => AppConfig.apiBaseUrl;

  /// Upload image and start recognition job
  Future<String> startRecognitionJob(File imageFile) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        imageFile.path,
        filename: 'hand.jpg',
      ),
    });

    final response = await _dio.post(
      '$_baseUrl/api/v1/recognize',
      data: formData,
    );

    return response.data['job_id'] as String;
  }

  /// Poll recognition job status
  Future<RecognizeJobStatus> getJobStatus(String jobId) async {
    final response = await _dio.get(
      '$_baseUrl/api/v1/recognize/$jobId',
    );
    return RecognizeJobStatus.fromJson(response.data);
  }

  /// Poll until job completes, returns RecognizeResponse
  Future<RecognizeResponse> waitForRecognition(
    String jobId, {
    Duration pollInterval = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final status = await getJobStatus(jobId);

      if (status.status == 'completed' && status.result != null) {
        return status.result!;
      }
      if (status.status == 'failed') {
        throw Exception('Recognition failed: ${status.error ?? "unknown"}');
      }
      if (status.status == 'canceled') {
        throw Exception('Recognition was canceled');
      }

      await Future.delayed(pollInterval);
    }

    throw TimeoutException('Recognition timed out after $timeout');
  }

  /// Calculate score from hand data
  Future<ScoreResponse> calculateScore(ScoreRequest request) async {
    final response = await _dio.post(
      '$_baseUrl/api/v1/score',
      data: request.toJson(),
    );
    return ScoreResponse.fromJson(response.data);
  }
}
