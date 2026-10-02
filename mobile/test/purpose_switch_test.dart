import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/interpretation_request.dart';
import 'package:tsumoai_mobile/models/scan_purpose.dart';
import 'package:tsumoai_mobile/services/purpose_switch.dart';

void main() {
  group('purposeSwitchAdjustment', () {
    test('reuses tiles between purposes with the same base count', () {
      expect(
        purposeSwitchAdjustment(ScanPurpose.score, ScanPurpose.discard),
        PurposeSwitchAdjustment.none,
      );
      expect(
        purposeSwitchAdjustment(ScanPurpose.wait, ScanPurpose.callAdvice),
        PurposeSwitchAdjustment.none,
      );
    });

    test('14-tile to 13-tile purposes leave one tile out', () {
      for (final from in [ScanPurpose.score, ScanPurpose.discard]) {
        for (final to in [ScanPurpose.wait, ScanPurpose.callAdvice]) {
          expect(
            purposeSwitchAdjustment(from, to),
            PurposeSwitchAdjustment.removeOne,
          );
        }
      }
    });

    test('13-tile to 14-tile purposes add one drawn tile', () {
      for (final from in [ScanPurpose.wait, ScanPurpose.callAdvice]) {
        for (final to in [ScanPurpose.score, ScanPurpose.discard]) {
          expect(
            purposeSwitchAdjustment(from, to),
            PurposeSwitchAdjustment.addOne,
          );
        }
      }
    });
  });

  test('removeSlot shifts later slots left and clears the last slot', () {
    final slots = <String?>['1m', '2m', '3m', '4m', null];
    removeSlot<String?>(slots, 1, null);
    expect(slots, ['1m', '3m', '4m', null, null]);
  });

  test('observation ids after the removed slot are renumbered', () {
    expect(shiftObservationIdAfterRemoval('tile-002', 5), 'tile-002');
    expect(shiftObservationIdAfterRemoval('tile-005', 5), isNull);
    expect(shiftObservationIdAfterRemoval('tile-013', 5), 'tile-012');
    expect(shiftObservationIdAfterRemoval(null, 5), isNull);
  });

  test('melds survive a concealed removal with shifted observation ids', () {
    const pon = ConfirmedMeld(
      observationIds: ['tile-010', 'tile-011', 'tile-012'],
      type: 'pon',
      open: true,
    );
    const chi = ConfirmedMeld(
      observationIds: ['tile-000', 'tile-001', 'tile-002'],
      type: 'chi',
      open: true,
    );

    final shifted = shiftMeldsAfterRemoval([chi, pon], 4);

    expect(shifted, hasLength(2));
    expect(shifted[0].observationIds, ['tile-000', 'tile-001', 'tile-002']);
    expect(shifted[1].observationIds, ['tile-009', 'tile-010', 'tile-011']);
    expect(shifted[1].type, 'pon');
    expect(shifted[1].open, isTrue);

    expect(shiftMeldsAfterRemoval([pon], 11), isEmpty);
  });
}
