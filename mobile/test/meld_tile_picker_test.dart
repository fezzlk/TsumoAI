import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/models/interpretation_request.dart';
import 'package:tsumoai_mobile/widgets/meld_tile_picker.dart';

import 'test_utils/landscape_surface.dart';

void main() {
  // Regression test for a real on-device bug: with enough available tiles
  // (kan hands can have up to 18), the sheet's content overflowed the
  // screen's actual landscape height and pushed the confirm/cancel row
  // below the visible area, with no way to reach it. Caught here via
  // `flutter test` alone — no simulator/device needed.
  testWidgets(
    'MeldTilePicker: confirm/cancel stay reachable at real device landscape size, even with many available tiles',
    (tester) async {
      ConfirmedMeld? result;
      await pumpAtDeviceLandscapeSize(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await MeldTilePicker.show(
                    context,
                    // Worst case: 18 available tiles (kan hand).
                    availableIndices: List.generate(18, (i) => i),
                    tileCodeOf: (i) => const [
                      '1m', '2m', '3m', '4m', '5m', '6m', '7m', '8m', '9m',
                      '1p', '2p', '3p', '4p', '5p', '6p', '7p', '8p', '9p',
                    ][i],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expectNoOverflow(tester);

      // The confirm/cancel row must actually exist in the tree and be
      // within the visible surface (not just present but scrolled/clipped
      // off past the sheet's edge).
      expect(find.text('確定'), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);
      final confirmRect = tester.getRect(find.text('確定'));
      expect(
        confirmRect.bottom,
        lessThanOrEqualTo(kLandscapeTestSize.height),
        reason: '確定 button must be within the screen, not pushed off-screen',
      );

      // Select 3 tiles (default type is ポン, expects 3) and confirm.
      for (final index in [0, 1, 2]) {
        await tester.tap(find.text('${index + 1}').first);
        await tester.pump();
      }
      expectNoOverflow(tester);
      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.observationIds, [
        'tile-000',
        'tile-001',
        'tile-002',
      ]);
    },
  );
}
