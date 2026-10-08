import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/services/hand_error_messages.dart';

void main() {
  test('tile-count refusals name the check and the count', () {
    expect(
      describeHandError('closed_tiles must contain 13 tiles for call analysis'),
      '鳴き判断は副露を除く手牌が13枚のときに行えます。牌の枚数を見直してください。',
    );
    expect(
      describeHandError(
        'closed_tiles must contain 14 tiles for discard analysis',
      ),
      contains('何を切る'),
    );
    expect(
      describeHandError(
        'Total tiles must be 14 at win state (14 + number of kans)',
      ),
      contains('14枚'),
    );
  });

  test('five of a tile names the tile in Japanese', () {
    expect(
      describeHandError('tile appears more than four times: 5pr'),
      '赤5筒が5枚以上あります。牌の識別結果を見直してください。',
    );
    expect(
      describeHandError('Tile appears 5+ times in hand: C'),
      startsWith('中が5枚以上'),
    );
  });

  test('condition conflicts and no-yaku get their own message', () {
    expect(describeHandError('tenhou requires dealer'), '天和は親（自風が東）のときだけ選べます。');
    expect(
      describeHandError('No yaku: dora-only hands cannot win'),
      contains('役がない'),
    );
    expect(describeHandError(notWinningShapeDetail), '上がりの形になっていません');
  });

  test('unknown messages keep the original text', () {
    expect(describeHandError('something new'), '入力内容を確認してください（something new）');
  });
}
