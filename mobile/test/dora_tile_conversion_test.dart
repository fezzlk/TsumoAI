import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/services/tile_assets.dart';

void main() {
  test('indicator and dora conversion wraps suits, winds, and dragons', () {
    expect(doraTileFromIndicator('9m'), '1m');
    expect(doraIndicatorFromTile('1m'), '9m');
    expect(doraTileFromIndicator('N'), 'E');
    expect(doraIndicatorFromTile('E'), 'N');
    expect(doraTileFromIndicator('C'), 'P');
    expect(doraIndicatorFromTile('P'), 'C');
  });

  test('red fives are normalized when entered as a dora tile', () {
    expect(doraIndicatorFromTile('5mr'), '4m');
  });
}
