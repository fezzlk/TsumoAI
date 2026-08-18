import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/screens/scan_screen.dart';

void main() {
  group('expectedPitchFromReferenceFrame', () {
    test('returns null when the preview size has not been measured yet', () {
      expect(expectedPitchFromReferenceFrame(null, 4760), isNull);
    });

    test('returns the reference frame height unchanged at equal pixel density', () {
      // previewSize.height == decodedImageWidth => 1:1 density, so the
      // result should equal the on-screen reference frame's own height
      // (90.0, see _kReferenceFrameHeight in scan_screen.dart).
      final pitch = expectedPitchFromReferenceFrame(const Size(400, 800), 800);
      expect(pitch, closeTo(90.0, 1e-9));
    });

    test('scales up when the captured image has a higher pixel density than the preview', () {
      final pitch = expectedPitchFromReferenceFrame(const Size(400, 800), 1600);
      expect(pitch, closeTo(180.0, 1e-9));
    });
  });
}
