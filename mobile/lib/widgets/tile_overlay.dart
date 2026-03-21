import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/tile_detector.dart';

/// Draws detected tile bounding boxes over the camera preview.
///
/// The rotation mapping between sensor coordinates and screen coordinates
/// depends on the device/camera. Use [rotationIndex] to cycle through
/// 4 possible rotations (0°, 90°CW, 180°, 90°CCW) until the overlay
/// aligns with the preview.
class TileOverlay extends StatelessWidget {
  final TileDetectorResult result;

  /// 0 = no rotation, 1 = 90° CW, 2 = 180°, 3 = 90° CCW
  final int rotationIndex;

  const TileOverlay({
    super.key,
    required this.result,
    this.rotationIndex = 3, // default: 90° CCW (typical for iOS rear camera)
  });

  @override
  Widget build(BuildContext context) {
    if (result.tileCount <= 0 ||
        result.imageWidth <= 0 ||
        result.imageHeight <= 0 ||
        result.bandSpanWidth <= 0 ||
        result.bandSpanHeight <= 0) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewW = constraints.maxWidth;
        final viewH = constraints.maxHeight;
        final imgW = result.imageWidth.toDouble();
        final imgH = result.imageHeight.toDouble();

        // After rotation, determine the displayed image dimensions and mapping.
        late final double dispW, dispH;
        late final Offset Function(double ix, double iy) imgToScreen;

        switch (rotationIndex % 4) {
          case 0: // No rotation
            dispW = imgW;
            dispH = imgH;
            imgToScreen = (ix, iy) => Offset(ix, iy);
            break;
          case 1: // 90° CW
            dispW = imgH;
            dispH = imgW;
            imgToScreen = (ix, iy) => Offset(imgH - 1 - iy, ix);
            break;
          case 2: // 180°
            dispW = imgW;
            dispH = imgH;
            imgToScreen = (ix, iy) => Offset(imgW - 1 - ix, imgH - 1 - iy);
            break;
          case 3: // 90° CCW
            dispW = imgH;
            dispH = imgW;
            imgToScreen = (ix, iy) => Offset(iy, imgW - 1 - ix);
            break;
        }

        final scaleX = viewW / dispW;
        final scaleY = viewH / dispH;

        Offset toScreen(double ix, double iy) {
          final p = imgToScreen(ix, iy);
          return Offset(p.dx * scaleX, p.dy * scaleY);
        }

        final tiles = <Widget>[];

        // Use per-tile rects from detector if available, else fall back to equal division
        final rects = result.tileRects;
        final useRects = rects.isNotEmpty && rects.length == result.tileCount;

        for (int i = 0; i < result.tileCount; i++) {
          double imgL, imgT, imgR, imgB;

          if (useRects) {
            imgL = rects[i].left;
            imgT = rects[i].top;
            imgR = imgL + rects[i].width;
            imgB = imgT + rects[i].height;
          } else if (result.axis == ScanAxis.horizontal) {
            final tileW = result.bandSpanWidth / result.tileCount;
            imgL = result.bandLeft + i * tileW;
            imgT = result.bandTop.toDouble();
            imgR = imgL + tileW;
            imgB = imgT + result.bandSpanHeight;
          } else {
            final tileH = result.bandSpanHeight / result.tileCount;
            imgL = result.bandLeft.toDouble();
            imgT = result.bandTop + i * tileH;
            imgR = imgL + result.bandSpanWidth;
            imgB = imgT + tileH;
          }

          final p1 = toScreen(imgL, imgT);
          final p2 = toScreen(imgR, imgB);

          final sL = math.min(p1.dx, p2.dx);
          final sT = math.min(p1.dy, p2.dy);
          final sW = (p1.dx - p2.dx).abs();
          final sH = (p1.dy - p2.dy).abs();

          if (sL + sW < 0 || sL > viewW || sT + sH < 0 || sT > viewH) {
            continue;
          }

          tiles.add(Positioned(
            left: sL,
            top: sT,
            width: sW,
            height: sH,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.greenAccent.withValues(alpha: 0.7),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.center,
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  color: Colors.greenAccent.withValues(alpha: 0.9),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  shadows: const [
                    Shadow(color: Colors.black, blurRadius: 3),
                  ],
                ),
              ),
            ),
          ));
        }

        return Stack(children: tiles);
      },
    );
  }
}
