import 'package:flutter/material.dart';
import 'tile_keyboard.dart';

/// Row of 14 tile slots showing classification results.
/// Each slot is tappable to manually override via tile keyboard.
class TileSlotRow extends StatelessWidget {
  final List<String?> tiles; // null = not yet classified
  final List<bool> isClassifying; // true = currently classifying
  final ValueChanged<int> onSlotTap;

  const TileSlotRow({
    super.key,
    required this.tiles,
    required this.isClassifying,
    required this.onSlotTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(14, (i) {
        final tile = i < tiles.length ? tiles[i] : null;
        final loading = i < isClassifying.length && isClassifying[i];
        final isWinTile = i == 13;

        return Expanded(
          child: GestureDetector(
            onTap: () => onSlotTap(i),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 0.5),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: tile != null
                    ? Colors.white.withOpacity(0.9)
                    : Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(3),
                border: isWinTile
                    ? Border.all(color: Colors.greenAccent, width: 1.5)
                    : null,
              ),
              alignment: Alignment.center,
              child: loading
                  ? const SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white54),
                    )
                  : Text(
                      tile != null ? _displayLabel(tile) : '?',
                      style: TextStyle(
                        fontSize: tile != null ? 11 : 13,
                        fontWeight: FontWeight.bold,
                        color: tile != null ? Colors.black87 : Colors.white38,
                      ),
                    ),
            ),
          ),
        );
      }),
    );
  }

  static String _displayLabel(String tile) {
    const honorLabels = {
      'E': '東', 'S': '南', 'W': '西', 'N': '北',
      'P': '白', 'F': '發', 'C': '中',
    };
    if (honorLabels.containsKey(tile)) return honorLabels[tile]!;
    return tile;
  }

  /// Show tile keyboard for a specific slot.
  static Future<String?> showKeyboardForSlot(
    BuildContext context, {
    String? currentTile,
  }) {
    return TileKeyboard.show(context, currentTile: currentTile);
  }
}
