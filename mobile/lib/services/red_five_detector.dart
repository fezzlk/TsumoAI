import 'package:image/image.dart' as img;

/// Red fives (赤5) are told apart after classification: the model knows the
/// 34 base tiles only (red fives are trained as their plain five), so a crop
/// classified as 5m/5p/5s becomes 5mr/5pr/5sr when almost all of its ink is
/// red. Plain fives mix red with black (萬), blue (筒) or green (索).
///
/// On the 179 real-camera fives in the training store (2026-10-04) red
/// fives scored 0.88–1.00 and plain fives at most 0.69 (萬) / 0.25 (筒・索);
/// see `scripts/evaluate_red_five.py`.
const double redFiveThreshold = 0.8;

const _plainFives = {'5m', '5p', '5s'};

/// Share of the tile's ink that is red, from 0 to 1.
///
/// Looks at the central 76% of the tile (skipping edges and shadows) at a
/// small fixed size. Ink is dark or faded-grey print plus clearly coloured
/// pixels; red is coloured with a hue near 0°.
double redInkShare(img.Image tile) {
  final small = img.copyResize(
    tile,
    width: 96,
    height: 128,
    interpolation: img.Interpolation.linear,
  );
  final x0 = (96 * 0.12).toInt(), x1 = (96 * 0.88).toInt();
  final y0 = (128 * 0.12).toInt(), y1 = (128 * 0.88).toInt();
  var ink = 0;
  var red = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final p = small.getPixel(x, y);
      final r = p.r / 255.0, g = p.g / 255.0, b = p.b / 255.0;
      final max = [r, g, b].reduce((a, c) => a > c ? a : c);
      final min = [r, g, b].reduce((a, c) => a < c ? a : c);
      final value = max;
      final saturation = max == 0 ? 0.0 : (max - min) / max;
      final dark = value < 0.35 || (value < 0.62 && saturation < 0.3);
      final coloured = saturation > 0.35 && value > 0.25;
      if (!dark && !coloured) continue;
      ink++;
      if (coloured && _isRedHue(r, g, b, max, min)) red++;
    }
  }
  return ink == 0 ? 0.0 : red / ink;
}

/// Hue within about ±18° of red (0.05 / 0.93 of the circle, as evaluated).
bool _isRedHue(double r, double g, double b, double max, double min) {
  if (max != r || max == min) return false;
  var hue = ((g - b) / (max - min)) / 6.0; // red sector: -1/6 .. 1/6
  if (hue < 0) hue += 1.0;
  return hue < 0.05 || hue > 0.93;
}

/// [tileCode] as a red five when it is a plain five whose crop is mostly red.
String refineRedFive(String tileCode, double redShare) =>
    _plainFives.contains(tileCode) && redShare >= redFiveThreshold
    ? '${tileCode}r'
    : tileCode;

/// Whether [tileCode] is one of the plain fives that may be a red five.
bool mayBeRedFive(String tileCode) => _plainFives.contains(tileCode);
