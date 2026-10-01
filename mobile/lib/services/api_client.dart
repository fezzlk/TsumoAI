import 'dart:io';
import 'package:dio/dio.dart';
import '../config.dart';
import '../models/recognize_result.dart';
import '../models/interpretation_request.dart';
import '../models/interpretation_result.dart';
import '../models/score_request.dart';
import '../models/score_result.dart';
import '../models/ai_chat_message.dart';
import '../models/ai_usage_status.dart';
import 'app_preferences.dart';
import 'auth_service.dart';

class ApiClient {
  final Dio _dio;
  final String? _baseUrlOverride;
  final Future<String> Function() _installationIdProvider;
  final Future<String?> Function() _authTokenProvider;

  ApiClient({
    Dio? dio,
    String? baseUrl,
    Future<String> Function()? installationIdProvider,
    Future<String?> Function()? authTokenProvider,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 60),
             ),
           ),
       _baseUrlOverride = baseUrl,
       _installationIdProvider =
           installationIdProvider ?? AppPreferences.installationId,
       _authTokenProvider = authTokenProvider ?? _currentAuthToken;

  String get _baseUrl => _baseUrlOverride ?? AppConfig.apiBaseUrl;

  static Future<String?> _currentAuthToken() async {
    if (AuthService.currentUser == null) return null;
    return AuthService.idToken();
  }

  Future<Map<String, String>> _aiHeaders() async {
    final headers = <String, String>{
      'X-TsumoAI-Install-ID': await _installationIdProvider(),
    };
    final token = await _authTokenProvider();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

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

  Future<InterpretationResult> interpret(InterpretationRequest request) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/api/v1/interpretations',
        data: request.toJson(),
      );
      return InterpretationResult.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (error) {
      final response = error.response;
      if (response == null) rethrow;
      final data = response.data;
      String message = 'Interpretation request failed';
      Object? details = data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is String) {
          message = detail;
        } else if (detail != null) {
          message = 'Interpretation request was rejected';
          details = detail;
        }
      }
      throw InterpretationApiException(
        statusCode: response.statusCode,
        message: message,
        details: details,
      );
    }
  }

  Future<ConfirmedHandStateV1> confirmHand({
    required InterpretationRequest request,
  }) async {
    final confirmation = request.confirmation;
    if (confirmation == null) {
      throw ArgumentError('Confirmation is required');
    }
    try {
      final response = await _dio.post(
        '$_baseUrl/api/v1/confirmed-hands',
        data: {
          'observation': request.observation.toJson(),
          'confirmation': confirmation.toJson(),
        },
      );
      return ConfirmedHandStateV1.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on DioException catch (error) {
      throw _interpretationException(error);
    }
  }

  Future<Map<String, dynamic>> analyzeTenpai({
    required ConfirmedHandStateV1 state,
    required ContextInput context,
    required RuleSet rules,
  }) async {
    final response = await _dio.post(
      '$_baseUrl/api/v1/tenpai/analyze',
      data: _analysisPayload(state, context, rules),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> analyzeDiscards({
    required ConfirmedHandStateV1 state,
    required ContextInput context,
    required RuleSet rules,
  }) async {
    final response = await _dio.post(
      '$_baseUrl/api/v1/discards/analyze',
      data: _analysisPayload(state, context, rules),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> analyzeCalls({
    required ConfirmedHandStateV1 state,
    required ContextInput context,
    required RuleSet rules,
  }) async {
    final response = await _dio.post(
      '$_baseUrl/api/v1/calls/analyze',
      data: _analysisPayload(state, context, rules),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<String> askAi({
    required String message,
    required List<AIChatMessage> conversation,
    required String purpose,
    required List<String> tiles,
    required Map<String, dynamic> roundContext,
    required Map<String, dynamic> analysis,
    required List<String> situationTags,
  }) async {
    try {
      final response = await _dio.post(
        '$_baseUrl/api/v1/ai-chat',
        options: Options(headers: await _aiHeaders()),
        data: {
          'message': message,
          'conversation': conversation
              .map((item) => item.toJson())
              .toList(growable: false),
          'context': {
            'purpose': purpose,
            'tiles': tiles,
            'round_context': roundContext,
            'analysis': analysis,
            'situation_tags': situationTags,
          },
        },
      );
      return (response.data as Map)['answer'] as String;
    } on DioException catch (error) {
      final data = error.response?.data;
      if (error.response?.statusCode == 429 && data is Map) {
        final detail = data['detail'];
        if (detail is Map && detail['code'] == 'monthly_ai_limit_reached') {
          throw AIQuotaExceededException(
            AIUsageStatus.fromJson(
              Map<String, dynamic>.from(detail['usage'] as Map),
            ),
          );
        }
      }
      rethrow;
    }
  }

  Future<AIUsageStatus> fetchAiUsage() async {
    final response = await _dio.get(
      '$_baseUrl/api/v1/ai-chat/usage',
      options: Options(headers: await _aiHeaders()),
    );
    return AIUsageStatus.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Map<String, dynamic> _analysisPayload(
    ConfirmedHandStateV1 state,
    ContextInput context,
    RuleSet rules,
  ) => {
    'closed_tiles': state.hand.closedTiles,
    'melds': state.hand.melds
        .map((meld) => meld.toAnalysisJson())
        .toList(growable: false),
    'context': context.toJson(),
    'rules': rules.toJson(),
    'include_score_predictions': true,
  };

  InterpretationApiException _interpretationException(DioException error) {
    final response = error.response;
    if (response == null) {
      return InterpretationApiException(
        statusCode: null,
        message: error.message ?? 'Network request failed',
      );
    }
    final data = response.data;
    String message = 'Confirmation request failed';
    Object? details = data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail != null) {
        message = 'Confirmation request was rejected';
        details = detail;
      }
    }
    return InterpretationApiException(
      statusCode: response.statusCode,
      message: message,
      details: details,
    );
  }

  /// Send recognition feedback with corrected tiles.
  Future<void> sendRecognitionFeedback({
    required Map<String, dynamic> recognitionResponse,
    required List<String> correctedTiles,
    String comment = '',
  }) async {
    final token = await AuthService.idToken(interactive: true);
    await _dio.post(
      '$_baseUrl/api/v1/recognition/feedback',
      data: {
        'recognition_response': recognitionResponse,
        'corrected_tiles': correctedTiles,
        'comment': comment,
      },
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }
}

class AIQuotaExceededException implements Exception {
  const AIQuotaExceededException(this.usage);

  final AIUsageStatus usage;
}

class InterpretationApiException implements Exception {
  final int? statusCode;
  final String message;
  final Object? details;

  const InterpretationApiException({
    required this.statusCode,
    required this.message,
    this.details,
  });

  @override
  String toString() => statusCode == null
      ? message
      : 'Interpretation API error ($statusCode): $message';
}
