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

  // Regression test for the follow-up jitter report: two real fingers
  // moving the same shared edge are never in perfect lock-step, so the
  // shared edge must land on the AVERAGE of both handles' own positions —
  // not flip between the two raw values depending on which handle's touch
  // event happened to arrive last.
  testWidgets(
    'PhotoCropScreen: dragging two handles that share an edge by slightly different amounts averages that edge, not last-writer-wins',
    (tester) async {
      final getResult = await openCropScreen(tester);

      final bottomLeftCenter = tester.getCenter(
        find.byKey(const ValueKey('crop-handle-bottomLeft')),
      );
      final bottomRightCenter = tester.getCenter(
        find.byKey(const ValueKey('crop-handle-bottomRight')),
      );

      final gestureBottomLeft = await tester.startGesture(bottomLeftCenter);
      final gestureBottomRight = await tester.startGesture(bottomRightCenter);
      await tester.pump();

      // Same direction (both up), slightly different magnitudes — as two
      // independent fingers always are in practice, even when the user
      // intends one single synchronized motion.
      await gestureBottomLeft.moveBy(const Offset(0, -20));
      await tester.pump();
      await gestureBottomRight.moveBy(const Offset(0, -24));
      await tester.pump();

      await gestureBottomLeft.up();
      await gestureBottomRight.up();
      await tester.pump();

      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();

      final region = getResult();
      expect(region, isNotNull);
      // Average of -20 and -24 is -22 — not -20 (bottomLeft's own value,
      // what last-writer-wins would give if bottomLeft's event happened to
      // be the most recent) and not -24 (bottomRight's).
      expect(
        region!.bottom,
        closeTo(_initialRegion.bottom - 22, 2),
        reason: 'bottom should average both fingers\' positions',
      );
    },
  );

  // Regression test for the follow-up "goes back to the original position"
  // report: lifting a handle mid-drag and touching it again must continue
  // from where it left off, not restart that handle's own delta at zero
  // measured against the session's original baseline.
  testWidgets(
    'PhotoCropScreen: lifting and re-touching a handle continues its movement instead of resetting it',
    (tester) async {
      final getResult = await openCropScreen(tester);

      final bottomLeftCenter = tester.getCenter(
        find.byKey(const ValueKey('crop-handle-bottomLeft')),
      );
      final bottomRightCenter = tester.getCenter(
        find.byKey(const ValueKey('crop-handle-bottomRight')),
      );

      // bottomRight: touches down and never moves for the whole test —
      // the "fixed finger" from the report.
      final gestureBottomRight = await tester.startGesture(bottomRightCenter);
      await tester.pump();

      // bottomLeft: moves up by 30, then lifts and touches down again to
      // move a further 10.
      var gestureBottomLeft = await tester.startGesture(bottomLeftCenter);
      await tester.pump();
      await gestureBottomLeft.moveBy(const Offset(0, -30));
      await tester.pump();
      await gestureBottomLeft.up();
      await tester.pump();

      gestureBottomLeft = await tester.startGesture(bottomLeftCenter);
      await tester.pump();
      await gestureBottomLeft.moveBy(const Offset(0, -10));
      await tester.pump();
      await gestureBottomLeft.up();
      await gestureBottomRight.up();
      await tester.pump();

      await tester.tap(find.text('確定'));
      await tester.pumpAndSettle();

      final region = getResult();
      expect(region, isNotNull);
      // bottomLeft's total displacement is 30+10=40; bottomRight never
      // moved (0) and was active throughout, so the shared `bottom` edge
      // averages to 20 up from the start — not ~5, which is what resetting
      // bottomLeft's delta to just its second touch's own -10 (averaged
      // with bottomRight's 0) would give.
      expect(
        region!.bottom,
        closeTo(_initialRegion.bottom - 20, 2),
        reason:
            'bottomLeft\'s movement across the lift/re-touch should accumulate to 40, not reset to 10',
      );
    },
  );
}
