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
      final client = ApiClient(dio: dio, baseUrl: 'https://example.test');

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
}
