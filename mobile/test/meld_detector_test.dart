import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/services/meld_detector.dart';

void main() {
  test('pon: three identical tiles', () {
    expect(detectMeldType(['3p', '3p', '3p']), MeldDetection.pon);
  });

  test('chi: three sequential same-suit tiles, any order', () {
    expect(detectMeldType(['4m', '3m', '5m']), MeldDetection.chi);
  });

  test('chi: red five counts as rank 5 of its suit', () {
    expect(detectMeldType(['3m', '4m', '5mr']), MeldDetection.chi);
  });

  test('kan: four identical tiles', () {
    expect(detectMeldType(['1s', '1s', '1s', '1s']), MeldDetection.kan);
  });

  test('invalid: mixed suits cannot form a chi', () {
    expect(detectMeldType(['3m', '4p', '5s']), MeldDetection.none);
  });

  test('invalid: non-sequential same-suit tiles', () {
    expect(detectMeldType(['1m', '2m', '4m']), MeldDetection.none);
  });

  test('invalid: honors cannot form a chi', () {
    expect(detectMeldType(['E', 'S', 'W']), MeldDetection.none);
  });

  test('invalid: three of one tile plus one different is not a kan', () {
    expect(detectMeldType(['2p', '2p', '2p', '3p']), MeldDetection.none);
  });

  test('invalid: two red fives are not a sequence (duplicate rank)', () {
    expect(detectMeldType(['5mr', '5mr', '4m']), MeldDetection.none);
  });

  test('degenerate sizes always return none', () {
    expect(detectMeldType([]), MeldDetection.none);
    expect(detectMeldType(['1m']), MeldDetection.none);
    expect(detectMeldType(['1m', '2m']), MeldDetection.none);
    expect(
      detectMeldType(['1m', '2m', '3m', '4m', '5m']),
      MeldDetection.none,
    );
  });
}
