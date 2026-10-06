import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'capture_framing.dart' show PreparedCapture;

/// Imported photos have no camera guide: preserve the entire oriented frame.
PreparedCapture prepareImportedPhoto(Uint8List bytes) {
  if (bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('画像は20MB以下で選んでください');
  }
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    throw const FormatException('画像を読み込めません。JPEGまたはPNGの写真を選んでください');
  }
  if (decoded == null) {
    throw const FormatException('画像を読み込めません。JPEGまたはPNGの写真を選んでください');
  }
  var image = img.bakeOrientation(decoded);
  if (image.width > 2048 || image.height > 2048) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 2048 : null,
      height: image.height > image.width ? 2048 : null,
    );
  }
  return (
    bytes: Uint8List.fromList(img.encodeJpg(image, quality: 95)),
    image: image,
  );
}
