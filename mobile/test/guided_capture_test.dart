import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/services/guided_capture.dart';

void main() {
  for (final count in [13, 14, 18]) {
    test(
      'guide boxes map into the same image coordinates for $count tiles',
      () {
        const preview = Size(368, 135);
        const photo = Size(1472, 540);
        final overlay = guidedTileBoxes(preview, count);
        final crops = guidedTileBoxes(photo, count);
        expect(overlay, hasLength(count));
        for (var index = 0; index < count; index++) {
          expect(crops[index].left, closeTo(overlay[index].left * 4, 0.001));
          expect(crops[index].top, closeTo(overlay[index].top * 4, 0.001));
          expect(crops[index].width, closeTo(overlay[index].width * 4, 0.001));
          expect(crops[index].right, lessThanOrEqualTo(photo.width));
          expect(crops[index].bottom, lessThanOrEqualTo(photo.height));
          if (index > 0) {
            expect(crops[index].left, greaterThan(crops[index - 1].right));
          }
        }
      },
    );
  }
}
