/// Maps a tile code (e.g. `1p`, `E`, `5mr`) to its illustration asset path
/// under `assets/tiles/`, or null if the code isn't recognized.
///
/// Ported from `app/static/tiles/tileToFilename` (the same filenames are
/// used — this mobile app vendors a copy of that web scoring tool's tile
/// image set rather than duplicating new artwork).
String? tileAssetPath(String tileCode) {
  final t = tileCode.trim();

  final redMatch = RegExp(r'^5([smpr])r$').firstMatch(t);
  if (redMatch != null) {
    return 'assets/tiles/Mpu0${redMatch.group(1)}.png';
  }

  if (RegExp(r'^[1-9][mps]$').hasMatch(t)) {
    return 'assets/tiles/Mpu${t[0]}${t[1]}.png';
  }

  const honors = {'E': '1', 'S': '2', 'W': '3', 'N': '4', 'P': '5', 'F': '6', 'C': '7'};
  final honor = honors[t];
  if (honor != null) {
    return 'assets/tiles/Mpu${honor}z.png';
  }

  return null;
}

const _tileDisplayNames = <String, String>{
  '1m': '一萬', '2m': '二萬', '3m': '三萬', '4m': '四萬', '5m': '五萬',
  '6m': '六萬', '7m': '七萬', '8m': '八萬', '9m': '九萬', '5mr': '赤五萬',
  '1p': '一筒', '2p': '二筒', '3p': '三筒', '4p': '四筒', '5p': '五筒',
  '6p': '六筒', '7p': '七筒', '8p': '八筒', '9p': '九筒', '5pr': '赤五筒',
  '1s': '一索', '2s': '二索', '3s': '三索', '4s': '四索', '5s': '五索',
  '6s': '六索', '7s': '七索', '8s': '八索', '9s': '九索', '5sr': '赤五索',
  'E': '東', 'S': '南', 'W': '西', 'N': '北',
  'P': '白', 'F': '發', 'C': '中',
};

/// Japanese display name for a tile code (e.g. `N` -> `北`, `5mr` -> `赤五萬`),
/// or the raw code itself if unrecognized — used wherever a tile code needs
/// to be shown as text rather than its illustration (see `tileAssetPath`).
/// Never show a raw tile code to the user directly; always go through this.
String tileDisplayName(String tileCode) =>
    _tileDisplayNames[tileCode.trim()] ?? tileCode;
