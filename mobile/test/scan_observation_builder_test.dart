import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/tile_observation.dart';
import 'package:tsumoai_mobile/models/tile_quad.dart';
import 'package:tsumoai_mobile/services/scan_observation_builder.dart';

void main() {
  test('builds stable IDs, sorted candidates, bbox, and orientation', () {
    const quad = TileQuad(
      topLeft: Offset(10, 20),
      topRight: Offset(30, 40),
      bottomLeft: Offset(0, 50),
      bottomRight: Offset(20, 70),
    );

    final payload = buildScanObservationV1(
      imageWidth: 100,
      imageHeight: 100,
      tiles: const [
        ScanObservationInput(
          index: 2,
          candidates: [
            TileCandidate(tile: '2m', confidence: 0.2),
            TileCandidate(tile: '1m', confidence: 0.9),
          ],
          quad: quad,
        ),
      ],
    );

    final observation = payload.observations.single;
    expect(observation.observationId, 'tile-002');
    expect(observation.candidates.first.tile, '1m');
    expect(observation.bbox?.left, 0);
    expect(observation.bbox?.bottom, 70);
    expect(observation.rotationDegrees, closeTo(45, 0.0001));
    expect(observation.visualGroupId, isNull);
  });

  test('leaves unavailable geometry null', () {
    final payload = buildScanObservationV1(
      imageWidth: 100,
      imageHeight: 100,
      tiles: const [
        ScanObservationInput(
          index: 0,
          observationId: 'capture-a-tile-a',
          candidates: [TileCandidate(tile: 'E', confidence: 0.8)],
        ),
      ],
    );

    final observation = payload.observations.single;
    expect(observation.observationId, 'capture-a-tile-a');
    expect(observation.bbox, isNull);
    expect(observation.rotationDegrees, isNull);
  });

  test('rejects duplicate IDs and out-of-image geometry', () {
    expect(
      () => buildScanObservationV1(
        imageWidth: 100,
        imageHeight: 100,
        tiles: const [
          ScanObservationInput(index: 0, observationId: 'same', candidates: []),
          ScanObservationInput(index: 1, observationId: 'same', candidates: []),
        ],
      ),
      throwsArgumentError,
    );

    expect(
      () => buildScanObservationV1(
        imageWidth: 100,
        imageHeight: 100,
        tiles: [
          ScanObservationInput(
            index: 0,
            candidates: const [],
            quad: TileQuad.fromRect(const Rect.fromLTRB(90, 20, 110, 60)),
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}
