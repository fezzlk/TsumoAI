import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/interpretation_request.dart';
import 'package:tsumoai_mobile/models/interpretation_result.dart';
import 'package:tsumoai_mobile/models/tile_observation.dart';
import 'package:tsumoai_mobile/services/api_client.dart';

ObservationV1 observation() => const ObservationV1(
  image: ObservationImage(width: 100, height: 80),
  observations: [
    TileObservation(
      observationId: 'tile-000',
      index: 0,
      candidates: [TileCandidate(tile: '1m', confidence: 0.9)],
    ),
  ],
);

void main() {
  test('interpret posts V1 observations and parses response', () async {
    final dio = Dio();
    RequestOptions? captured;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'melds': [],
                'winning_tile': {
                  'observation_id': null,
                  'tile': null,
                  'status': 'unknown',
                  'confidence': 0.0,
                  'evidence': <String>[],
                },
                'requires_user_confirmation': true,
                'warnings': ['geometry_missing'],
              },
            ),
          );
        },
      ),
    );
    final client = ApiClient(dio: dio, baseUrl: 'https://example.test');

    final result = await client.interpret(
      InterpretationRequest(observation: observation()),
    );

    expect(captured?.path, 'https://example.test/api/v1/interpretations');
    final sent = captured?.data as Map<String, dynamic>;
    expect(sent['schema_version'], '1');
    expect((sent['observations'] as List), hasLength(1));
    expect(result.winningTile.status, FactStatus.unknown);
    expect(result.requiresUserConfirmation, isTrue);
    expect(result.warnings, ['geometry_missing']);
  });

  test('interpret exposes a displayable 422 error', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: 422,
                data: {
                  'detail': [
                    {
                      'loc': ['body', 'observations'],
                      'msg': 'invalid observation',
                    },
                  ],
                },
              ),
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );
    final client = ApiClient(dio: dio, baseUrl: 'https://example.test');

    expect(
      () => client.interpret(InterpretationRequest(observation: observation())),
      throwsA(
        isA<InterpretationApiException>()
            .having((error) => error.statusCode, 'statusCode', 422)
            .having(
              (error) => error.message,
              'message',
              'Interpretation request was rejected',
            )
            .having((error) => error.details, 'details', isNotNull),
      ),
    );
  });

  test(
    'confirmHand posts separate observation and confirmation documents',
    () async {
      final dio = Dio();
      RequestOptions? captured;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'schema_version': '1',
                  'operation': 'score',
                  'hand': {
                    'closed_tiles': ['1m'],
                    'closed_tile_observation_ids': ['tile-000'],
                    'melds': [],
                    'win_tile': '1m',
                    'win_tile_observation_id': 'tile-000',
                  },
                },
              ),
            );
          },
        ),
      );
      final client = ApiClient(dio: dio, baseUrl: 'https://example.test');
      const confirmation = ConfirmationV1(
        operation: HandOperation.score,
        confirmedTiles: [ConfirmedTile(observationId: 'tile-000', tile: '1m')],
        confirmedWinningTileId: 'tile-000',
      );

      final state = await client.confirmHand(
        request: InterpretationRequest(
          observation: observation(),
          confirmation: confirmation,
        ),
      );

      expect(captured?.path, 'https://example.test/api/v1/confirmed-hands');
      final sent = captured?.data as Map<String, dynamic>;
      expect((sent['observation'] as Map)['schema_version'], '1');
      expect((sent['confirmation'] as Map)['operation'], 'score');
      expect(state.hand.winTileObservationId, 'tile-000');
    },
  );
}
