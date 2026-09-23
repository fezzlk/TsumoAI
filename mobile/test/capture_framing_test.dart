import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tsumoai_mobile/services/capture_framing.dart';

void main() {
  test('portrait capture is center-cropped to the preview frame', () {
    final source = img.Image(width: 1600, height: 2400);
    img.fill(source, color: img.ColorRgb8(255, 0, 0));
    img.fillRect(
      source,
      x1: 0,
      y1: 750,
      x2: 1599,
      y2: 1649,
      color: img.ColorRgb8(0, 255, 0),
    );

    final framed = cropToCaptureFrame(source);

    expect(framed.width, 1600);
    expect(framed.height, 900);
    expect(framed.width / framed.height, captureFrameAspectRatio);
    expect(framed.getPixel(800, 450).g, 255);
  });

  test('prepared bytes and result image use the same guide region', () {
    final portrait = img.Image(width: 800, height: 1200);
    final encoded = Uint8List.fromList(img.encodeJpg(portrait));

    final prepared = prepareCapturedFrame(encoded);
    final decodedResult = img.decodeJpg(prepared.bytes);

    expect(prepared.image.width, 736);
    expect(prepared.image.height, 270);
    expect(decodedResult, isNotNull);
    expect(decodedResult!.width, prepared.image.width);
    expect(decodedResult.height, prepared.image.height);
    expect(prepared.image.width, greaterThan(prepared.image.height));
  });

  test('capture guide excludes pixels outside the visible green box', () {
    final preview = img.Image(width: 1600, height: 900);
    img.fill(preview, color: img.ColorRgb8(255, 0, 0));
    img.fillRect(
      preview,
      x1: 64,
      y1: 270,
      x2: 1535,
      y2: 809,
      color: img.ColorRgb8(0, 255, 0),
    );

    final guide = cropToCaptureGuide(preview);

    expect(guide.width, 1472);
    expect(guide.height, 540);
    expect(guide.getPixel(0, 0).g, 255);
    expect(guide.getPixel(guide.width - 1, guide.height - 1).g, 255);
  });

  test('already framed capture keeps its dimensions', () {
    final source = img.Image(width: 1920, height: 1080);

    final framed = cropToCaptureFrame(source);

    expect(framed.width, 1920);
    expect(framed.height, 1080);
  });
}
