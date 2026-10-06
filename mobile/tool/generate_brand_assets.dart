// Run from mobile/: dart run tool/generate_brand_assets.dart
// Packaging only: keep the approved source artwork unchanged.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

final _root = File.fromUri(Platform.script).parent.parent;
File _file(String path) => File('${_root.path}/$path');
const _background = 0xE8F2ED;

void _write(String path, List<int> bytes) {
  final file = _file(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}

void main() {
  final source = img.decodePng(
    _file('assets/branding/tsumorou_source.png').readAsBytesSync(),
  )!;
  // Trim transparent export margins, without altering the illustration.
  var left = source.width, top = source.height, right = 0, bottom = 0;
  for (final p in source) {
    if (p.a <= 16) continue;
    left = math.min(left, p.x);
    top = math.min(top, p.y);
    right = math.max(right, p.x);
    bottom = math.max(bottom, p.y);
  }
  if (left > right || top > bottom) {
    throw StateError('The source illustration is empty.');
  }
  final art = img.copyCrop(
    source,
    x: left,
    y: top,
    width: right - left + 1,
    height: bottom - top + 1,
  );
  var radius = 0.0;
  for (final p in art) {
    if (p.a <= 16) continue;
    final dx = p.x - art.width / 2;
    final dy = p.y - art.height / 2;
    radius = math.max(radius, math.sqrt(dx * dx + dy * dy));
  }

  img.Image canvas(int size, {bool transparent = false, double? safeRadius}) {
    final result = img.Image(
      width: size,
      height: size,
      numChannels: transparent ? 4 : 3,
    );
    if (!transparent) {
      img.fill(
        result,
        color: img.ColorRgb8(
          _background >> 16,
          (_background >> 8) & 255,
          _background & 255,
        ),
      );
    }
    final scale = safeRadius != null
        ? size * safeRadius / radius
        : size * (transparent ? 0.90 : 0.84) / math.max(art.width, art.height);
    final resized = img.copyResize(
      art,
      width: (art.width * scale).round(),
      height: (art.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
    img.compositeImage(
      result,
      resized,
      dstX: (size - resized.width) ~/ 2,
      dstY: (size - resized.height) ~/ 2,
    );
    return result;
  }

  void png(String path, img.Image image) => _write(path, img.encodePng(image));

  png('assets/branding/tsumorou.png', canvas(256, transparent: true));
  for (final platform in ['ios', 'macos']) {
    final dir = '$platform/Runner/Assets.xcassets/AppIcon.appiconset';
    final catalog = jsonDecode(_file('$dir/Contents.json').readAsStringSync());
    final written = <String>{};
    for (final entry in catalog['images'] as List) {
      final name = entry['filename'] as String;
      if (!written.add(name)) continue;
      final points = double.parse((entry['size'] as String).split('x').first);
      final scale = double.parse(
        (entry['scale'] as String).replaceAll('x', ''),
      );
      // Opaque RGB, including the iOS 1024px App Store icon.
      png('$dir/$name', canvas((points * scale).round()));
    }
  }
  for (final entry in {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  }.entries) {
    png(
      'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
      canvas(entry.value),
    );
  }
  // Android's central 66/108 safe circle protects the hat under all masks.
  png(
    'android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png',
    canvas(432, transparent: true, safeRadius: 0.30),
  );
  for (final size in [192, 512]) {
    png('web/icons/Icon-$size.png', canvas(size));
    // Web maskable icons retain all artwork inside the central 80% circle.
    png('web/icons/Icon-maskable-$size.png', canvas(size, safeRadius: 0.38));
  }
  png('web/favicon.png', canvas(32));
  _write(
    'windows/runner/resources/app_icon.ico',
    img.IcoEncoder().encodeImages([
      for (final size in [16, 24, 32, 48, 64, 128, 256]) canvas(size),
    ]),
  );
  stdout.writeln('Generated Tsumorou assets from the approved source.');
}
