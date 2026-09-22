import 'dart:typed_data';

import 'package:image/image.dart' as img;

const double captureFrameAspectRatio = 16 / 9;

typedef PreparedCapture = ({Uint8List bytes, img.Image image});

PreparedCapture prepareCapturedFrame(Uint8List sourceBytes) {
  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) throw const FormatException('画像のデコードに失敗');
  final oriented = img.bakeOrientation(decoded);
  final framed = cropToCaptureFrame(oriented);
  return (
    bytes: Uint8List.fromList(img.encodeJpg(framed, quality: 95)),
    image: framed,
  );
}

img.Image cropToCaptureFrame(
  img.Image source, {
  double targetAspectRatio = captureFrameAspectRatio,
}) {
  if (targetAspectRatio <= 0) {
    throw ArgumentError.value(
      targetAspectRatio,
      'targetAspectRatio',
      '0より大きい必要があります',
    );
  }

  final sourceAspectRatio = source.width / source.height;
  if ((sourceAspectRatio - targetAspectRatio).abs() < 0.0001) {
    return img.copyCrop(
      source,
      x: 0,
      y: 0,
      width: source.width,
      height: source.height,
    );
  }

  if (sourceAspectRatio > targetAspectRatio) {
    final width = (source.height * targetAspectRatio).round().clamp(
      1,
      source.width,
    );
    return img.copyCrop(
      source,
      x: (source.width - width) ~/ 2,
      y: 0,
      width: width,
      height: source.height,
    );
  }

  final height = (source.width / targetAspectRatio).round().clamp(
    1,
    source.height,
  );
  return img.copyCrop(
    source,
    x: 0,
    y: (source.height - height) ~/ 2,
    width: source.width,
    height: height,
  );
}
