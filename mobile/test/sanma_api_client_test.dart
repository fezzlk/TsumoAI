import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/score_request.dart';
import 'package:tsumoai_mobile/models/interpretation_result.dart';
import 'package:tsumoai_mobile/services/api_client.dart';

void main() {
  test('old server cannot silently receive sanma score requests', () async {
    final paths = <String>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          paths.add(request.path);
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              data: {
                'mahjong_variants': ['yonma'],
              },
            ),
          );
        },
      ),
    );
    final api = ApiClient(dio: dio, baseUrl: 'https://example.test');
    await expectLater(
      api.calculateScore(
        ScoreRequest(
          hand: HandInput(
            closedTiles: const ['N'],
            melds: const [],
            winTile: 'N',
          ),
          context: ContextInput(),
          rules: const RuleSet(variant: 'sanma'),
        ),
      ),
      throwsStateError,
    );
    expect(paths, ['https://example.test/api/v1/capabilities']);
  });

  test('sanma analysis carries rules and manually extracted north', () async {
    Map<String, dynamic>? sent;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          if (request.path.endsWith('capabilities')) {
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: {
                  'mahjong_variants': ['yonma', 'sanma'],
                },
              ),
            );
          } else {
            sent = Map<String, dynamic>.from(request.data as Map);
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: {'shanten': 0},
              ),
            );
          }
        },
      ),
    );
    final state = ConfirmedHandStateV1.fromJson({
      'schema_version': '1',
      'operation': 'tenpai',
      'hand': {
        'closed_tiles': ['N'],
        'closed_tile_observation_ids': ['tile-000'],
        'melds': [],
      },
    });
    await ApiClient(dio: dio, baseUrl: 'https://example.test').analyzeTenpai(
      state: state,
      context: ContextInput(),
      rules: const RuleSet(variant: 'sanma'),
      extractedTiles: const ['N', 'N'],
    );
    expect(sent!['extracted_tiles'], ['N', 'N']);
    expect((sent!['rules'] as Map)['variant'], 'sanma');
    expect(sent!['closed_tiles'], ['N']);
  });
}
