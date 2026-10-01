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
            expect(options.headers['X-TsumoAI-Install-ID'], 'install-12345678');
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
        installationIdProvider: () async => 'install-12345678',
        authTokenProvider: () async => null,
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
      installationIdProvider: () async => 'install-12345678',
      authTokenProvider: () async => 'firebase-token',
    );

    final usage = await client.fetchAiUsage();

    expect(usage.remaining, 2);
    expect(usage.includedUsed, 1);
  });
}
