import 'dart:ui';

/// Fixed tile slots shared by the camera overlay and captured-image crops.
/// Both callers pass the size of the already cropped capture-guide region.
List<Rect> guidedTileBoxes(Size size, int count) {
  if (size.width <= 0 || size.height <= 0 || count < 1 || count > 18) {
    throw ArgumentError('invalid guided capture dimensions or tile count');
  }
  final gap = size.width * 0.004;
  final rowWidth = size.width * 0.94;
  final tileWidth = (rowWidth - gap * (count - 1)) / count;
  final tileHeight = tileWidth / 0.73;
  final left = (size.width - rowWidth) / 2;
  final top = (size.height - tileHeight) / 2;
  return List.generate(
    count,
    (index) => Rect.fromLTWH(
      left + index * (tileWidth + gap),
      top,
      tileWidth,
      tileHeight,
    ),
  );
}
