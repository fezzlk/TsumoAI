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
