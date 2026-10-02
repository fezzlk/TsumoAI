import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/services/tile_detector.dart';

void main() {
  TileDetectorResult detection({
    int count = 14,
    int left = 40,
    int top = 80,
    int width = 320,
    int height = 90,
    ScanAxis axis = ScanAxis.horizontal,
  }) => TileDetectorResult(
    tileCount: count,
    bandLength: width,
    bandThickness: height,
    estimatedTileWidth: width / count,
    axis: axis,
    bandLeft: left,
    bandTop: top,
    bandSpanWidth: width,
    bandSpanHeight: height,
    imageWidth: 400,
    imageHeight: 300,
    tileRects: [
      for (var index = 0; index < count; index++)
        TileRect(
          left: left + (width / count) * index,
          top: top.toDouble(),
          width: width / count,
          height: height.toDouble(),
        ),
    ],
  );

  test('stable detections tolerate small frame-to-frame movement', () {
    expect(
      detectionsAreStable(detection(), detection(left: 44, top: 83)),
      isTrue,
    );
  });

  test(
    'stability rejects changes in position, size, count, or orientation',
    () {
      final baseline = detection();
      expect(detectionsAreStable(baseline, detection(left: 90)), isFalse);
      expect(detectionsAreStable(baseline, detection(width: 240)), isFalse);
      expect(detectionsAreStable(baseline, detection(count: 13)), isFalse);
      expect(
        detectionsAreStable(baseline, detection(axis: ScanAxis.vertical)),
        isFalse,
      );
    },
  );
}
