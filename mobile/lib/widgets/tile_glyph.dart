import 'package:flutter/material.dart';
import '../services/tile_assets.dart';

/// Renders a tile code as its illustration (`tileAssetPath`), falling back
/// to its Japanese name (`tileDisplayName`) when the code isn't recognized
/// — the shared image-or-text convention used everywhere a tile code needs
/// to be shown to the user.
class TileGlyph extends StatelessWidget {
  final String tileCode;
  final TextStyle? fallbackTextStyle;

  const TileGlyph({super.key, required this.tileCode, this.fallbackTextStyle});

  @override
  Widget build(BuildContext context) {
    final path = tileAssetPath(tileCode);
    if (path == null) {
      return Center(
        child: Text(tileDisplayName(tileCode), style: fallbackTextStyle),
      );
    }
    return Image.asset(path, fit: BoxFit.contain);
  }
}
