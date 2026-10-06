import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tsumoai_mobile/services/photo_import.dart';

void main() {
  test(
    'import preserves the full photo instead of cropping the camera guide',
    () {
      final source = img.Image(width: 400, height: 300);
      img.fill(source, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(
        source,
        x1: 0,
        y1: 0,
        x2: 40,
        y2: 40,
        color: img.ColorRgb8(255, 0, 0),
      );
      final result = prepareImportedPhoto(
        Uint8List.fromList(img.encodePng(source)),
      );
      expect(result.image.width, 400);
      expect(result.image.height, 300);
      expect(result.image.getPixel(10, 10).g, 0);
      expect(img.decodeJpg(result.bytes), isNotNull);
    },
  );
  test('large photos are bounded without changing aspect ratio', () {
    final result = prepareImportedPhoto(
      Uint8List.fromList(img.encodePng(img.Image(width: 2400, height: 1200))),
    );
    expect(result.image.width, 2048);
    expect(result.image.height, 1024);
  });
  test('invalid or oversized inputs report a recoverable format error', () {
    expect(
      () => prepareImportedPhoto(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(
      () => prepareImportedPhoto(Uint8List(20 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
  });
}
