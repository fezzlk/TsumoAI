import 'package:flutter/material.dart';

/// Tile selection keyboard shown as a BottomSheet.
/// Allows user to manually select a mahjong tile code.
class TileKeyboard extends StatelessWidget {
  final String? currentTile;
  final ValueChanged<String> onTileSelected;

  const TileKeyboard({
    super.key,
    this.currentTile,
    required this.onTileSelected,
  });

  static Future<String?> show(BuildContext context, {String? currentTile}) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => TileKeyboard(
        currentTile: currentTile,
        onTileSelected: (tile) => Navigator.pop(context, tile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
      child: Column(
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
          _buildRow('萬', [for (int i = 1; i <= 9; i++) '${i}m']),
          const SizedBox(height: 6),
          _buildRow('筒', [for (int i = 1; i <= 9; i++) '${i}p']),
          const SizedBox(height: 6),
          _buildRow('索', [for (int i = 1; i <= 9; i++) '${i}s']),
          const SizedBox(height: 6),
          _buildRow('字', ['E', 'S', 'W', 'N', 'P', 'F', 'C']),
        ],
      ),
    );
  }

  Widget _buildRow(String label, List<String> tiles) {
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ),
        ...tiles.map((tile) => Expanded(
          child: GestureDetector(
            onTap: () => onTileSelected(tile),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: tile == currentTile
                    ? Colors.green.withOpacity(0.4)
                    : Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: tile == currentTile
                    ? Border.all(color: Colors.greenAccent, width: 1.5)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                _displayLabel(tile),
                style: TextStyle(
                  color: tile == currentTile ? Colors.greenAccent : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        )),
        // Pad honor row to match 9 columns
        if (tiles.length < 9)
          ...List.generate(9 - tiles.length, (_) => const Expanded(child: SizedBox())),
      ],
    );
  }

  String _displayLabel(String tile) {
    const honorLabels = {
      'E': '東', 'S': '南', 'W': '西', 'N': '北',
      'P': '白', 'F': '發', 'C': '中',
    };
    if (honorLabels.containsKey(tile)) return honorLabels[tile]!;
    return tile;
  }
}
