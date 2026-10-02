import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/services/official_ai_chat_template_service.dart';

void main() {
  test('downloads and caches versioned official templates', () async {
    final directory = await Directory.systemTemp.createTemp('ai-template-');
    addTearDown(() => directory.delete(recursive: true));
    var requests = 0;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'version': 7,
                'items': [
                  {
                    'id': 'question-test',
                    'kind': 'question',
                    'purpose': 'discard',
                    'label': 'テスト質問',
                    'body': 'テスト質問です',
                    'enabled': true,
                    'sort_order': 0,
                  },
                ],
              },
            ),
          );
        },
      ),
    );
    final service = OfficialAIChatTemplateService(
      dio: dio,
      directoryProvider: () async => directory,
    );

    final remote = await service.load();
    final cached = await service.load(refresh: false);

    expect(requests, 1);
    expect(remote.version, 7);
    expect(cached.items.single.label, 'テスト質問');
  });

  test('uses bundled defaults when refresh fails', () async {
    final directory = await Directory.systemTemp.createTemp('ai-template-');
    addTearDown(() => directory.delete(recursive: true));
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) =>
            handler.reject(DioException(requestOptions: options)),
      ),
    );
    final service = OfficialAIChatTemplateService(
      dio: dio,
      directoryProvider: () async => directory,
    );

    final config = await service.load();

    expect(config.items, isNotEmpty);
    expect(config.items.any((item) => item.label == '着順UP'), isTrue);
  });
}
