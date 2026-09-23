import 'dart:typed_data';

import 'package:image/image.dart' as img;

const double captureFrameAspectRatio = 16 / 9;
const double captureGuideLeftFactor = 0.04;
const double captureGuideTopFactor = 0.30;
const double captureGuideWidthFactor = 0.92;
const double captureGuideHeightFactor = 0.60;

typedef PreparedCapture = ({Uint8List bytes, img.Image image});

PreparedCapture prepareCapturedFrame(Uint8List sourceBytes) {
  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) throw const FormatException('画像のデコードに失敗');
  final oriented = img.bakeOrientation(decoded);
  final previewFrame = cropToCaptureFrame(oriented);
  final framed = cropToCaptureGuide(previewFrame);
  return (
    bytes: Uint8List.fromList(img.encodeJpg(framed, quality: 95)),
    image: framed,
  );
}

/// Crops the visible 16:9 preview to the green guide shown to the user.
/// Detection, classification and result editing all receive this same image,
/// so reflections or table edges outside the guide cannot become tile boxes.
img.Image cropToCaptureGuide(img.Image previewFrame) {
  final x = (previewFrame.width * captureGuideLeftFactor).round();
  final y = (previewFrame.height * captureGuideTopFactor).round();
  final width = (previewFrame.width * captureGuideWidthFactor).round().clamp(
    1,
    previewFrame.width - x,
  );
  final height = (previewFrame.height * captureGuideHeightFactor).round().clamp(
    1,
    previewFrame.height - y,
  );
  return img.copyCrop(previewFrame, x: x, y: y, width: width, height: height);
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
