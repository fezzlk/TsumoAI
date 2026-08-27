import 'package:flutter/material.dart';
import '../services/tile_assets.dart';

/// Image-based tile selection, shown as a BottomSheet — same grid-by-suit
/// layout as `TileKeyboard`, but each button shows the tile's illustration
/// (`tileAssetPath`) instead of a text label.
class TileImagePicker extends StatelessWidget {
  final String? currentTile;
  final ValueChanged<String> onTileSelected;

  const TileImagePicker({
    super.key,
    this.currentTile,
    required this.onTileSelected,
  });

  static const _manRow = ['1m', '2m', '3m', '4m', '5m', '5mr', '6m', '7m', '8m', '9m'];
  static const _pinRow = ['1p', '2p', '3p', '4p', '5p', '5pr', '6p', '7p', '8p', '9p'];
  static const _souRow = ['1s', '2s', '3s', '4s', '5s', '5sr', '6s', '7s', '8s', '9s'];
  static const _honorRow = ['E', 'S', 'W', 'N', 'P', 'F', 'C'];
  static const _columns = 10;

  static Future<String?> show(BuildContext context, {String? currentTile}) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      builder: (_) => TileImagePicker(
        currentTile: currentTile,
        onTileSelected: (tile) => Navigator.pop(context, tile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Cell size is derived from the AVAILABLE HEIGHT, not the row's
          // width — sized to fit exactly 4 suit rows in whatever vertical
          // space the sheet has (a short landscape screen included), rather
          // than growing with a wide sheet's width and overflowing. Cells
          // are then a fixed size and the row just uses however much width
          // that needs, instead of stretching to fill it.
          const headerHeight = 4.0 + 12 + 18 + 12; // handle + spacing + label + spacing
          const rowSpacing = 6.0;
          final gridHeight = constraints.maxHeight - headerHeight - rowSpacing * 3;
          final cellHeight = (gridHeight / 4 - 6).clamp(28.0, 64.0);
          final cellWidth = cellHeight * 0.75;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              const Text('牌を選択', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 12),
              _buildRow('萬', _manRow, cellWidth, cellHeight),
              const SizedBox(height: rowSpacing),
              _buildRow('筒', _pinRow, cellWidth, cellHeight),
              const SizedBox(height: rowSpacing),
              _buildRow('索', _souRow, cellWidth, cellHeight),
              const SizedBox(height: rowSpacing),
              _buildRow('字', _honorRow, cellWidth, cellHeight),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRow(String label, List<String> tiles, double cellWidth, double cellHeight) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 20,
          child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ),
        ...tiles.map((tile) => GestureDetector(
          onTap: () => onTileSelected(tile),
          child: Container(
            width: cellWidth,
            height: cellHeight,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: tile == currentTile
                  ? Colors.green.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: tile == currentTile
                  ? Border.all(color: Colors.greenAccent, width: 1.5)
                  : null,
            ),
            alignment: Alignment.center,
            child: _tileImage(tile),
          ),
        )),
        // Pad honor row to match the suit rows' column count.
        if (tiles.length < _columns)
          SizedBox(width: (cellWidth + 2) * (_columns - tiles.length)),
      ],
    );
  }

  Widget _tileImage(String tile) {
    final path = tileAssetPath(tile);
    if (path == null) return const SizedBox.shrink();
    return Image.asset(path, fit: BoxFit.contain);
  }
}
