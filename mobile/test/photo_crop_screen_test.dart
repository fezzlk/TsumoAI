import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tsumoai_mobile/screens/photo_crop_screen.dart';

import 'test_utils/landscape_surface.dart';

final _rawImageBytes = img.encodePng(
  img.Image(width: 400, height: 300)..clear(img.ColorRgb8(200, 200, 200)),
);

const _initialRegion = Rect.fromLTWH(50, 40, 200, 150);

/// Pumps a screen with a button that pushes [PhotoCropScreen], taps it, and
/// returns a getter for whatever the route eventually pops.
Future<Rect? Function()> openCropScreen(WidgetTester tester) async {
  Rect? result;
  await pumpAtDeviceLandscapeSize(
    tester,
    Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<Rect>(
                MaterialPageRoute(
                  builder: (_) => PhotoCropScreen(
                    rawImageBytes: _rawImageBytes,
                    rawWidth: 400,
                    rawHeight: 300,
                    initialRegion: _initialRegion,
                  ),
                ),
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
  return () => result;
}

void main() {
  // Regression test for FEZ-93: topLeft and bottomLeft both own the
  // region's `left` edge. Dragging both simultaneously (two fingers, same
  // direction, same distance — the reported "moves twice as far" scenario)
  // must move `left` by that one distance, not by double it.
  testWidgets(
    'PhotoCropScreen: dragging two handles that share an edge, in the same direction, does not double that edge\'s movement',
    (tester) async {
      final getResult = await openCropScreen(tester);

      final topLeftCenter = tester.getCenter(
        find.byKey(const ValueKey('crop-handle-topLeft')),
      );
      final bottomLeftCenter = tester.getCenter(
        find.byKey(const ValueKey('crop-handle-bottomLeft')),
      );

      final gestureTopLeft = await tester.startGesture(topLeftCenter);
      final gestureBottomLeft = await tester.startGesture(bottomLeftCenter);
      await tester.pump();

      const moveBy = Offset(-30, 0);
      await gestureTopLeft.moveBy(moveBy);
      await gestureBottomLeft.moveBy(moveBy);
      await tester.pump();

      await gestureTopLeft.up();
      await gestureBottomLeft.up();
      await tester.pump();

      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();

      final region = getResult();
      expect(region, isNotNull);
      // The screen-to-image scale here is 1:1 (400-wide photo, ample
      // viewport), so a -30 screen-px swipe should move `left` by ~30
      // image px — not ~60, which is what the pre-fix incremental-on-live-
      // region math produced for this exact two-finger, same-edge, same-
      // direction case.
      expect(
        region!.left,
        closeTo(_initialRegion.left - 30, 2),
        reason: 'left should move by one swipe\'s worth, not double',
      );
    },
  );
}
