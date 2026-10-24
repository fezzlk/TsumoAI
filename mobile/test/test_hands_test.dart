import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tsumoai_mobile/services/test_hand_image.dart';
import 'package:tsumoai_mobile/services/test_hands.dart';
import 'package:tsumoai_mobile/services/tile_assets.dart';

String _physical(String tile) =>
    tile.endsWith('r') ? tile.substring(0, 2) : tile;

void main() {
  test('every test hand is 14 known tiles with at most 4 of each', () {
    for (final hand in testHands) {
      expect(hand.tiles, hasLength(14), reason: hand.label);
      final counts = <String, int>{};
      for (final tile in hand.tiles) {
        expect(tileAssetPath(tile), isNotNull, reason: '${hand.label}: $tile');
        counts.update(_physical(tile), (n) => n + 1, ifAbsent: () => 1);
      }
      for (final entry in counts.entries) {
        expect(
          entry.value,
          lessThanOrEqualTo(4),
          reason: '${hand.label}: ${entry.key}',
        );
      }
    }
  });

  test('三人麻雀 hands avoid 2m-8m and 北', () {
    final banned = {for (var n = 2; n <= 8; n++) '${n}m', '5mr', 'N'};
    final hands = testHandsFor(sanma: true);
    expect(hands, isNotEmpty);
    for (final hand in hands) {
      expect(hand.tiles.where(banned.contains), isEmpty, reason: hand.label);
    }
  });

  test('13-tile purposes take the first 13 tiles', () {
    final hand = testHands.first;
    expect(hand.tilesFor(13), hand.tiles.take(13).toList());
  });

  test('renders one non-overlapping box per tile', () async {
    final tiles = testHands.first.tiles;
    final rendered = await renderTestHand(
      tiles,
      loadAsset: (path) => File(path).readAsBytes(),
    );
    expect(rendered.boxes, hasLength(tiles.length));
    for (var i = 1; i < rendered.boxes.length; i++) {
      expect(rendered.boxes[i].left, greaterThan(rendered.boxes[i - 1].right));
    }
    expect(rendered.boxes.last.right, lessThan(rendered.image.width));
    expect(rendered.bytes, isNotEmpty);
  });
}
