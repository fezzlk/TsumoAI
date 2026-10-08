/// A hand the server refused (HTTP 422), with a message for the user.
class HandRequestException implements Exception {
  const HandRequestException(this.message, {this.detail});

  final String message;

  /// The server's original message, for telling refusals apart.
  final Object? detail;

  /// The hand is a winning shape but has no 役 under these conditions.
  bool get isNoYaku => detail == noYakuDetail;

  @override
  String toString() => message;
}

/// The server's score message for a hand that simply isn't a winning shape;
/// only this one means 「上がりの形になっていません」.
const notWinningShapeDetail = 'Hand is not a valid winning shape';

/// The server's score message for a winning shape without any 役.
const noYakuDetail = 'No yaku: dora-only hands cannot win';

const _tileNames = {
  'E': '東',
  'S': '南',
  'W': '西',
  'N': '北',
  'P': '白',
  'F': '發',
  'C': '中',
};

String _tileName(String code) {
  if (_tileNames[code] case final name?) return name;
  final match = RegExp(r'^([1-9])([mps])(r?)$').firstMatch(code);
  if (match == null) return code;
  final suit = {'m': '萬', 'p': '筒', 's': '索'}[match.group(2)]!;
  return '${match.group(3)!.isEmpty ? '' : '赤'}${match.group(1)}$suit';
}

/// Japanese text for the server's hand validation messages (`detail` of a
/// 422). Unknown messages keep the original after a generic lead.
String describeHandError(Object? detail) {
  final text = detail?.toString() ?? '';
  final count = RegExp(
    r'closed_tiles must contain (\d+) tiles for (\w+) analysis',
  ).firstMatch(text);
  if (count != null) {
    final purpose = switch (count.group(2)) {
      'tenpai' => '待ち確認',
      'discard' => '何を切る',
      'call' => '鳴き判断',
      _ => '確認',
    };
    return '$purposeは副露を除く手牌が${count.group(1)}枚のときに行えます。牌の枚数を見直してください。';
  }
  final total = RegExp(r'Total tiles must be (\d+)').firstMatch(text);
  if (total != null) {
    return '点数計算は和了時の${total.group(1)}枚（槓子1つにつき+1枚）で行います。牌の枚数を見直してください。';
  }
  final tooMany = RegExp(
    r'(?:tile appears more than four times|Tile appears 5\+ times in hand): (\S+)',
  ).firstMatch(text);
  if (tooMany != null) {
    return '${_tileName(tooMany.group(1)!)}が5枚以上あります。牌の識別結果を見直してください。';
  }
  final invalid = RegExp(r'Invalid tile code: (\S+)').firstMatch(text);
  if (invalid != null) {
    return '識別できない牌（${invalid.group(1)}）があります。牌を修正してください。';
  }
  const known = {
    notWinningShapeDetail: '上がりの形になっていません',
    'No yaku: dora-only hands cannot win': '役がないため和了できません（ドラだけでは上がれません）。',
    'A hand cannot contain more than four declared melds': '副露は4つまでです。',
    'riichi and double_riichi cannot both be true': '立直とダブル立直は同時に選べません。',
    'riichi/double_riichi require a closed hand (no open melds)':
        '立直は門前（鳴いていない手）でのみ選べます。副露か立直を見直してください。',
    'ippatsu cannot be true when riichi/double_riichi is false':
        '一発は立直しているときだけ選べます。',
    'haitei cannot be true on ron': '海底摸月はツモのときだけ有効です。',
    'rinshan cannot be true on ron': '嶺上開花はツモのときだけ有効です。',
    'houtei cannot be true on tsumo': '河底撈魚はロンのときだけ有効です。',
    'chankan cannot be true on tsumo': '槍槓はロンのときだけ有効です。',
    'chiihou and tenhou cannot both be true': '天和と地和は同時に選べません。',
    'chiihou/tenhou require tsumo': '天和・地和はツモのときだけ有効です。',
    'tenhou requires dealer': '天和は親（自風が東）のときだけ選べます。',
    'chiihou requires non-dealer': '地和は子（自風が東以外）のときだけ選べます。',
    'win_tile must be present in closed_tiles': 'あがり牌が手牌にありません。あがり牌を選び直してください。',
  };
  if (known[text] case final message?) return message;
  return '入力内容を確認してください（$text）';
}
