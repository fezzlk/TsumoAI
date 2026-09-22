import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app is portrait-first. `flutter test`'s default
/// surface is 800x600 logical points — comfortably larger in both
/// dimensions than many real phones — so an overflow that's
/// invisible in a plain `tester.pumpWidget(...)` call can still crash or
/// hide content on the real device, only discoverable after a full
/// build+install cycle.
///
/// Both pulled from the actual on-device verification hardware
/// (`xcrun devicectl device info displays`: physical 1206x2622 at 3x
/// pointScale -> logical 402x874). Most screens are landscape-only
/// (app-wide default, `main.dart`), but at least one (single-tile
/// training-data capture) now allows portrait too — a fix that itself
/// caused a portrait-only overflow bug (`TileImagePicker`'s grid assumed
/// its row would always fit the available width, true only in landscape),
/// so both sizes matter, not just landscape.
///
/// [kLandscapeTestPadding]/[kPortraitTestPadding] approximate that
/// device's home-indicator safe-area inset (conservative; exact insets
/// aren't modeled here — this catches the common
/// "content doesn't fit" class of bug, not every possible safe-area edge
/// case).
const kLandscapeTestSize = Size(874, 402);
const kLandscapeTestPadding = EdgeInsets.only(bottom: 21);
const kPortraitTestSize = Size(402, 874);
const kPortraitTestPadding = EdgeInsets.only(bottom: 34);

/// Sets the test surface to [size]/[padding] for the duration of the test
/// (auto-restored via [WidgetTester.view]'s `reset()` in `addTearDown`),
/// then pumps [child] under a minimal `MaterialApp` so real widgets
/// (Scaffold, Navigator, Directionality, etc.) all resolve normally.
Future<void> pumpAtDeviceSize(
  WidgetTester tester,
  Widget child, {
  required Size size,
  required EdgeInsets padding,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  tester.view.padding = FakeViewPadding(
    bottom: padding.bottom * tester.view.devicePixelRatio,
  );
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: child));
}

/// Shorthand for [pumpAtDeviceSize] at [kLandscapeTestSize].
Future<void> pumpAtDeviceLandscapeSize(WidgetTester tester, Widget child) =>
    pumpAtDeviceSize(
      tester,
      child,
      size: kLandscapeTestSize,
      padding: kLandscapeTestPadding,
    );

/// Shorthand for [pumpAtDeviceSize] at [kPortraitTestSize].
Future<void> pumpAtDevicePortraitSize(WidgetTester tester, Widget child) =>
    pumpAtDeviceSize(
      tester,
      child,
      size: kPortraitTestSize,
      padding: kPortraitTestPadding,
    );

/// Fails the test if any widget in the current tree reports a layout
/// overflow (Flutter renders these as a "yellow and black stripes"
/// `RenderFlex overflowed` error, caught by [FlutterError.onError] rather
/// than thrown as a normal exception `flutter test` would already catch).
/// Call this after `pumpAndSettle()`/`pump()` following whatever
/// interaction you're testing.
///
/// Usage: wrap the test body's interactions between
/// `takeOverflowErrors(tester)` calls, or just call it once at the end —
/// [WidgetTester.takeException] only returns the *most recent* unhandled
/// error, so for multiple potential overflow points prefer asserting after
/// each pump rather than only once at the very end.
void expectNoOverflow(WidgetTester tester) {
  final exception = tester.takeException();
  if (exception == null) return;
  fail('Expected no layout overflow, but got: $exception');
}
