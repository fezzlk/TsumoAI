import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/ai_chat_message.dart';
import 'package:tsumoai_mobile/services/api_client.dart';

void main() {
  test(
    'askAi sends the current hand, analysis, tags and conversation',
    () async {
      final dio = Dio();
      Map<String, dynamic>? body;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            body = Map<String, dynamic>.from(options.data as Map);
            expect(options.headers['Authorization'], 'Bearer firebase-token');
            expect(
              options.headers.containsKey('X-TsumoAI-Install-ID'),
              isFalse,
            );
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'answer': '回答'},
              ),
            );
          },
        ),
      );
      final client = ApiClient(
        dio: dio,
        baseUrl: 'https://example.test',
        authTokenProvider: () async => 'firebase-token',
      );

      final answer = await client.askAi(
        message: '何を切る？',
        conversation: const [AIChatMessage(role: 'assistant', content: '前の回答')],
        purpose: 'discard',
        tiles: const ['1m', '2m'],
        roundContext: const {'round_wind': 'E'},
        analysis: const {'discards': []},
        situationTags: const ['守備優先'],
      );

      expect(answer, '回答');
      expect(body!['message'], '何を切る？');
      expect((body!['context'] as Map)['situation_tags'], ['守備優先']);
      expect((body!['conversation'] as List).single['content'], '前の回答');
    },
  );

  test('fetchAiUsage parses the monthly allowance', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'period': '2026-10',
              'plan': 'free',
              'included_limit': 3,
              'included_used': 1,
              'bonus_remaining': 0,
              'remaining': 2,
              'resets_at': '2026-11-01T00:00:00Z',
            },
          ),
        ),
      ),
    );
    final client = ApiClient(
      dio: dio,
      baseUrl: 'https://example.test',
      authTokenProvider: () async => 'firebase-token',
    );

    final usage = await client.fetchAiUsage();

    expect(usage.remaining, 2);
    expect(usage.includedUsed, 1);
  });

  test('askAi requires login before sending anything', () async {
    final dio = Dio();
    var requests = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests += 1;
          handler.reject(DioException(requestOptions: options));
        },
      ),
    );
    final client = ApiClient(
      dio: dio,
      baseUrl: 'https://example.test',
      authTokenProvider: () async => null,
    );

    await expectLater(
      client.askAi(
        message: '何を切る？',
        conversation: const [],
        purpose: 'discard',
        tiles: const ['1m'],
        roundContext: const {},
        analysis: const {},
        situationTags: const [],
      ),
      throwsA(isA<AILoginRequiredException>()),
    );
    await expectLater(
      client.fetchAiUsage(),
      throwsA(isA<AILoginRequiredException>()),
    );
    expect(requests, 0);
  });

  test('askAi sends only the most recent turns the server accepts', () async {
    final dio = Dio();
    Map<String, dynamic>? body;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          body = Map<String, dynamic>.from(options.data as Map);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'answer': '回答'},
            ),
          );
        },
      ),
    );
    final client = ApiClient(
      dio: dio,
      baseUrl: 'https://example.test',
      authTokenProvider: () async => 'firebase-token',
    );

    await client.askAi(
      message: '次は？',
      conversation: [
        for (var index = 0; index < 20; index++)
          AIChatMessage(
            role: index.isEven ? 'user' : 'assistant',
            content: 'message-$index',
          ),
      ],
      purpose: 'discard',
      tiles: const ['1m'],
      roundContext: const {},
      analysis: const {},
      situationTags: const [],
    );

    final sent = body!['conversation'] as List;
    expect(sent, hasLength(ApiClient.aiConversationLimit));
    expect(sent.first['content'], 'message-8');
    expect(sent.last['content'], 'message-19');
  });
}
