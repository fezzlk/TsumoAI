import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config.dart';
import 'auth_service.dart';

/// Sends one opt-in capture to the private diagnostic storage endpoint.
class ScanDiagnosticsClient {
  ScanDiagnosticsClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 60),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  final Dio _dio;

  Future<String> upload({
    required Uint8List rawImage,
    required Uint8List framedImage,
    required Map<String, Object?> metadata,
  }) async {
    final token = await AuthService.idToken();
    final response = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiBaseUrl}/api/v1/scan-diagnostics',
      data: FormData.fromMap({
        'raw_image': MultipartFile.fromBytes(rawImage, filename: 'raw.jpg'),
        'framed_image': MultipartFile.fromBytes(
          framedImage,
          filename: 'framed.jpg',
        ),
        'metadata': jsonEncode(metadata),
      }),
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return response.data!['capture_id'] as String;
  }

  Future<String> uploadLogs({
    required DateTime periodStart,
    required DateTime periodEnd,
    required List<Map<String, Object?>> entries,
  }) async {
    final token = await AuthService.idToken();
    final response = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.apiBaseUrl}/api/v1/scan-diagnostics/logs',
      data: {
        'period_start': periodStart.toUtc().toIso8601String(),
        'period_end': periodEnd.toUtc().toIso8601String(),
        'entries': entries,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return response.data!['log_id'] as String;
  }
}
