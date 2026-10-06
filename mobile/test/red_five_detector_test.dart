import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tsumoai_mobile/services/red_five_detector.dart';

/// A white tile face with [strokes] painted as horizontal bars.
img.Image _tile(List<img.Color> strokes) {
  final tile = img.Image(width: 120, height: 160)
    ..clear(img.ColorRgb8(245, 243, 236));
  for (var i = 0; i < strokes.length; i++) {
    img.fillRect(
      tile,
      x1: 30,
      y1: 30 + i * 30,
      x2: 90,
      y2: 45 + i * 30,
      color: strokes[i],
    );
  }
  return tile;
}

final _red = img.ColorRgb8(200, 30, 35);
final _black = img.ColorRgb8(25, 25, 25);
final _blue = img.ColorRgb8(30, 50, 140);
final _green = img.ColorRgb8(30, 120, 60);
final _grey = img.ColorRgb8(120, 120, 118);

void main() {
  test('all-red print is a red five', () {
    final share = redInkShare(_tile([_red, _red, _red, _red]));
    expect(share, greaterThan(redFiveThreshold));
    expect(refineRedFive('5p', share), '5pr');
  });

  test('red mixed with black, blue, green or faded grey stays plain', () {
    for (final other in [_black, _blue, _green, _grey]) {
      final share = redInkShare(_tile([other, _red, other, other]));
      expect(share, lessThan(redFiveThreshold), reason: '$other');
      expect(refineRedFive('5m', share), '5m');
    }
  });

  test('only plain fives are refined', () {
    expect(refineRedFive('3m', 1.0), '3m');
    expect(refineRedFive('C', 1.0), 'C');
    expect(refineRedFive('5mr', 1.0), '5mr');
    expect(mayBeRedFive('5s'), isTrue);
    expect(mayBeRedFive('5sr'), isFalse);
  });

  test('a blank tile has no ink', () {
    expect(redInkShare(_tile(const [])), 0.0);
  });
}
