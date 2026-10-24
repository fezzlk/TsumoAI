import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

import 'tile_assets.dart';

typedef TestHandImage = ({Uint8List bytes, img.Image image, List<Rect> boxes});

const int _margin = 24;
const int _gap = 6;

/// Lays the tile illustrations for [tiles] out in one row on a mat-green
/// background, standing in for a photo of the hand (FEZ-256). [boxes] holds
/// each tile's position in [image], in the same order as [tiles].
Future<TestHandImage> renderTestHand(
  List<String> tiles, {
  Future<Uint8List> Function(String assetPath)? loadAsset,
}) async {
  final load =
      loadAsset ??
      (String path) async => (await rootBundle.load(path)).buffer.asUint8List();
  final faces = <img.Image>[];
  for (final tile in tiles) {
    final path = tileAssetPath(tile);
    if (path == null) throw ArgumentError.value(tile, 'tiles', '未知の牌');
    final face = img.decodePng(await load(path));
    if (face == null) throw StateError('牌画像を読めません: $path');
    faces.add(face);
  }

  final tileHeight = faces.fold<int>(
    0,
    (max, f) => f.height > max ? f.height : max,
  );
  final width =
      _margin * 2 +
      faces.fold<int>(0, (sum, f) => sum + f.width) +
      _gap * (faces.length - 1);
  final canvas = img.Image(width: width, height: tileHeight + _margin * 2);
  img.fill(canvas, color: img.ColorRgb8(34, 92, 62));

  final boxes = <Rect>[];
  var x = _margin;
  for (final face in faces) {
    img.compositeImage(canvas, face, dstX: x, dstY: _margin);
    boxes.add(
      Rect.fromLTWH(
        x.toDouble(),
        _margin.toDouble(),
        face.width.toDouble(),
        face.height.toDouble(),
      ),
    );
    x += face.width + _gap;
  }

  final bytes = Uint8List.fromList(img.encodeJpg(canvas, quality: 95));
  return (bytes: bytes, image: canvas, boxes: boxes);
}
