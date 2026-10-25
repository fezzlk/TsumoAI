/// Fixed hands a developer can load instead of photographing real tiles
/// (FEZ-256), so scoring and result-screen changes can be checked on a
/// device without laying out a hand each time.
///
/// Every hand is concealed and 14 tiles long, ordered so the rightmost tile
/// is the あがり牌 (the results screen's default). Purposes that read 13
/// tiles use the first 13, which leaves a tenpai hand.
class TestHand {
  const TestHand({
    required this.label,
    required this.description,
    required this.tiles,
    this.sanma = false,
  });

  final String label;
  final String description;
  final List<String> tiles;

  /// Hands for 三人麻雀 avoid 2m–8m (and 北, which is counted separately).
  final bool sanma;

  /// The tiles for a purpose that reads [count] physical tiles.
  List<String> tilesFor(int count) => tiles.take(count).toList();
}

const List<TestHand> testHands = [
  TestHand(
    label: '平和',
    description: '34p 待ちに 5p であがり',
    tiles: [
      '2m', '3m', '4m', '5m', '6m', '7m', '3p', '4p', //
      '9p', '9p', '6s', '7s', '8s', '5p',
    ],
  ),
  TestHand(
    label: '平和・赤ドラ',
    description: '平和に赤五萬を1枚',
    tiles: [
      '2m', '3m', '4m', '5mr', '6m', '7m', '3p', '4p', //
      '9p', '9p', '6s', '7s', '8s', '5p',
    ],
  ),
  TestHand(
    label: '断么九',
    description: '78m 待ちに 6m であがり（暗刻あり）',
    tiles: [
      '2m', '2m', '2m', '5p', '6p', '7p', '3s', '4s', //
      '5s', '6s', '6s', '7m', '8m', '6m',
    ],
  ),
  TestHand(
    label: '役なし',
    description: 'カンチャン 8s。ロンは役なしで和了できない',
    tiles: [
      '1m', '2m', '3m', '7m', '8m', '9m', '4p', '5p', //
      '6p', '9s', '9s', '7s', '9s', '8s',
    ],
  ),
  TestHand(
    label: '七対子',
    description: '東の単騎待ち',
    tiles: [
      '1m', '1m', '3m', '3m', '5p', '5p', '7p', '7p', //
      '2s', '2s', '8s', '8s', 'E', 'E',
    ],
  ),
  TestHand(
    label: '混一色・一気通貫',
    description: '東の単騎待ち',
    tiles: [
      '1m', '2m', '3m', '4m', '5m', '6m', '7m', '8m', //
      '9m', 'S', 'S', 'S', 'E', 'E',
    ],
  ),
  TestHand(
    label: '清一色',
    description: '8m の単騎待ち',
    tiles: [
      '1m', '1m', '1m', '2m', '3m', '4m', '5m', '6m', //
      '7m', '9m', '9m', '9m', '8m', '8m',
    ],
  ),
  TestHand(
    label: '清一色・一気通貫',
    description: '5m の単騎待ち',
    tiles: [
      '1m', '2m', '3m', '4m', '5m', '6m', '7m', '8m', //
      '9m', '2m', '2m', '2m', '5m', '5m',
    ],
  ),
  TestHand(
    label: '四暗刻単騎',
    description: '中の単騎待ち',
    tiles: [
      '1m', '1m', '1m', '5p', '5p', '5p', '9s', '9s', //
      '9s', 'E', 'E', 'E', 'C', 'C',
    ],
  ),
  TestHand(
    label: '国士無双',
    description: '1m であがり',
    tiles: [
      '1m', '9m', '1p', '9p', '1s', '9s', 'E', 'S', //
      'W', 'N', 'P', 'F', 'C', '1m',
    ],
  ),
  TestHand(
    label: '平和（三人麻雀）',
    description: '34s 待ちに 5s であがり',
    sanma: true,
    tiles: [
      '2p', '3p', '4p', '5p', '6p', '7p', '3s', '4s', //
      '9p', '9p', '6s', '7s', '8s', '5s',
    ],
  ),
  TestHand(
    label: '混一色（三人麻雀）',
    description: '白の単騎待ち',
    sanma: true,
    tiles: [
      '1p', '2p', '3p', '5p', '6p', '7p', '9p', '9p', //
      '9p', 'S', 'S', 'S', 'P', 'P',
    ],
  ),
];

/// The hands offered for the current rules.
List<TestHand> testHandsFor({required bool sanma}) =>
    testHands.where((hand) => hand.sanma == sanma).toList();
