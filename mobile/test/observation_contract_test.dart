import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/interpretation_request.dart';
import 'package:tsumoai_mobile/models/recognize_result.dart';
import 'package:tsumoai_mobile/models/tile_observation.dart';

Map<String, dynamic> readFixture(String name) {
  final contents = File('../tests/fixtures/contracts/$name').readAsStringSync();
  return jsonDecode(contents) as Map<String, dynamic>;
}

void main() {
  test('ObservationV1 reads and writes the normative fixture', () {
    final payload = ObservationV1.fromJson(readFixture('observation-v1.json'));

    expect(payload.schemaVersion, '1');
    expect(payload.image.width, 1600);
    expect(payload.image.coordinateSpace, 'oriented_image_pixels');
    expect(payload.observations, hasLength(14));
    expect(payload.observations[4].candidates.first.tile, '5pr');
    expect(payload.observations[12].rotationDegrees, 90.0);
    expect(payload.observations[12].visualGroupId, 'group-001');
    expect(payload.toJson()['schema_version'], '1');
  });

  test('ConfirmationV1 reads and writes the normative fixture', () {
    final confirmation = ConfirmationV1.fromJson(
      readFixture('confirmation-v1.json'),
    );

    expect(confirmation.operation, HandOperation.score);
    expect(confirmation.confirmedTiles, hasLength(14));
    expect(confirmation.confirmedWinningTileId, 'tile-008');
    expect(confirmation.confirmedMelds.single.type, 'pon');
    expect(confirmation.toJson()['operation'], 'score');
  });

  test('unsupported contract versions are rejected', () {
    final payload = readFixture('observation-v1.json')
      ..['schema_version'] = '2';
    expect(() => ObservationV1.fromJson(payload), throwsFormatException);
  });

  test('recognition slots preserve optional server observation fields', () {
    final slot = HandSlot.fromJson({
      'index': 3,
      'top': '5pr',
      'candidates': [
        {'tile': '5pr', 'confidence': 0.88},
      ],
      'ambiguous': false,
      'observation_id': 'tile-003',
      'bbox': {'left': 10, 'top': 20, 'right': 30, 'bottom': 60},
      'rotation_degrees': 12.5,
      'visual_group_id': 'group-001',
    });

    expect(slot.observationId, 'tile-003');
    expect(slot.bbox?.right, 30.0);
    expect(slot.rotationDegrees, 12.5);
    expect(slot.visualGroupId, 'group-001');
  });
}
