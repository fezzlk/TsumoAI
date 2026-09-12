import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Draws detected tile bounding boxes over a static (already-captured)
/// hand photo. Boxes are given in the original image's pixel coordinate
/// space (i.e. [imageWidth]x[imageHeight]); this widget maps them onto
/// the displayed [Image.memory] rect (accounting for BoxFit.contain
/// letterboxing) rather than requiring the image to be shown at any
/// particular rotation/scale.
///
/// Purely a static overview — tapping a marker (via [onTap]) is expected to
/// open a dedicated full-screen editor (see `TileBoxEditorScreen`) rather
/// than dragging handles in place here; an earlier version did the latter
/// but it fought the surrounding scroll view and felt heavy in practice.
class TileMarkerOverlay extends StatelessWidget {
  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final List<Rect?> boxes;
  final List<String?> tiles;
  final void Function(int index)? onTap;

  const TileMarkerOverlay({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.boxes,
    required this.tiles,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (imageWidth <= 0 || imageHeight <= 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewW = constraints.maxWidth;
        final viewH = constraints.maxHeight;
        final imgAspect = imageWidth / imageHeight;
        final viewAspect = viewW / viewH;

        late final double dispW, dispH;
        if (imgAspect > viewAspect) {
          dispW = viewW;
          dispH = viewW / imgAspect;
        } else {
          dispH = viewH;
          dispW = viewH * imgAspect;
        }
        final dispLeft = (viewW - dispW) / 2;
        final dispTop = (viewH - dispH) / 2;
        final scale = dispW / imageWidth;

        final markers = <Widget>[];
        for (int i = 0; i < boxes.length; i++) {
          final box = boxes[i];
          if (box == null) continue;

          final left = dispLeft + box.left * scale;
          final top = dispTop + box.top * scale;
          final width = box.width * scale;
          final height = box.height * scale;

          Widget marker = Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.greenAccent.withValues(alpha: 0.85),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            alignment: Alignment.topLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              color: Colors.black.withValues(alpha: 0.55),
              child: Text(
                '${i + 1}',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );

          if (onTap != null) {
            marker = GestureDetector(onTap: () => onTap!(i), child: marker);
          }

          markers.add(Positioned(
            left: left,
            top: top,
            width: width,
            height: height,
            child: marker,
          ));
        }

        return Stack(
          children: [
            Positioned(
              left: dispLeft,
              top: dispTop,
              width: dispW,
              height: dispH,
              child: Image.memory(imageBytes, fit: BoxFit.fill, gaplessPlayback: true),
            ),
            ...markers,
          ],
        );
      },
    );
  }
}
