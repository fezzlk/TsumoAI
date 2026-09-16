import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/widgets/tile_image_picker.dart';

import 'test_utils/landscape_surface.dart';

void main() {
  // Regression test for a real on-device bug: TileImagePicker's cell size
  // was derived from available height only, assuming the resulting row
  // (label + 10 columns) would always fit the available width — true only
  // in landscape. Once a screen started allowing portrait too, the last
  // tiles of each suit row (e.g. 8m/9m) overflowed sideways with no
  // scroll, making them unreachable.
  testWidgets(
    'TileImagePicker: last tile of each suit row is on-screen and tappable at portrait device size',
    (tester) async {
      String? picked;
      await pumpAtDevicePortraitSize(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await TileImagePicker.show(context);
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

      // Last tile in each suit row (the ones that fell off-screen in the
      // original bug). Honors only has 7, so its last is 'C', not
      // width-constrained the same way, but included for completeness.
      for (final lastTile in ['9m', '9p', '9s', 'C']) {
        final finder = find.byKey(ValueKey('tile_picker_cell_$lastTile'));
        expect(
          finder,
          findsOneWidget,
          reason: '$lastTile should exist in the tree',
        );
        final rect = tester.getRect(finder);
        expect(
          rect.right,
          lessThanOrEqualTo(kPortraitTestSize.width),
          reason: '$lastTile must be within the portrait screen width, not pushed off to the right',
        );
      }

      await tester.tap(find.byKey(const ValueKey('tile_picker_cell_9m')));
      await tester.pumpAndSettle();
      expect(picked, '9m');
    },
  );
}
