import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../services/tile_assets.dart';

/// Image-based tile selection: 萬・筒・索 in rows of nine, then the honors
/// and the red fives as centred rows below, each cell drawn as a tile.
/// [show] opens it as a bottom sheet with a centred title and a close
/// button (tile-correction mockup).
class TileImagePicker extends StatelessWidget {
  final String? currentTile;
  final ValueChanged<String> onTileSelected;
  final String title;

  /// Whether the title row is drawn; off when a screen embeds the grid
  /// under its own heading.
  final bool showHeader;

  /// Shows a close button in the title row when set.
  final VoidCallback? onClose;

  const TileImagePicker({
    super.key,
    this.currentTile,
    required this.onTileSelected,
    this.title = '牌を選択',
    this.showHeader = true,
    this.onClose,
  });

  static const _rows = [
    ['1m', '2m', '3m', '4m', '5m', '6m', '7m', '8m', '9m'],
    ['1p', '2p', '3p', '4p', '5p', '6p', '7p', '8p', '9p'],
    ['1s', '2s', '3s', '4s', '5s', '6s', '7s', '8s', '9s'],
    ['E', 'S', 'W', 'N', 'P', 'F', 'C'],
    ['5mr', '5pr', '5sr'],
  ];
  static const _columns = 9;
  static const _rowSpacing = 4.0;
  static const _cellGap = 3.0;
  static const _headerHeight = 48.0;

  static Future<String?> show(
    BuildContext context, {
    String? currentTile,
    String title = '牌を選択',
  }) {
    return showModalBottomSheet<String>(
      context: context,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.95,
      ),
      builder: (sheetContext) => TileImagePicker(
        currentTile: currentTile,
        title: title,
        onTileSelected: (tile) => Navigator.pop(sheetContext, tile),
        onClose: () => Navigator.pop(sheetContext),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s,
        AppSpacing.s,
        AppSpacing.s,
        AppSpacing.m,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Cells are capped by both the available height (every row fits
          // without scrolling) and the width (a narrow portrait screen
          // must not push the ninth tile off the edge); the smaller wins.
          final header = showHeader ? _headerHeight + AppSpacing.s : 0.0;
          final gridHeight =
              constraints.maxHeight -
              header -
              _rowSpacing * (_rows.length - 1) -
              AppSpacing.s;
          final maxHeightPerCell = gridHeight / _rows.length;
          final maxWidthPerCell =
              (constraints.maxWidth - _cellGap * (_columns - 1)) /
              _columns /
              0.75;
          final cellHeight = math
              .min(maxHeightPerCell, maxWidthPerCell)
              .clamp(28.0, 76.0);
          final cellWidth = cellHeight * 0.75;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showHeader) ...[
                SizedBox(
                  height: _headerHeight,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (onClose != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            onPressed: onClose,
                            icon: const Icon(Icons.close),
                            tooltip: '閉じる',
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s),
              ],
              for (var i = 0; i < _rows.length; i++) ...[
                if (i == 3) const SizedBox(height: AppSpacing.s),
                if (i > 0) const SizedBox(height: _rowSpacing),
                _buildRow(context, _rows[i], cellWidth, cellHeight),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    List<String> tiles,
    double cellWidth,
    double cellHeight,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: _cellGap),
          Semantics(
            button: true,
            selected: tiles[i] == currentTile,
            label: tiles[i],
            child: GestureDetector(
              key: ValueKey('tile_picker_cell_${tiles[i]}'),
              onTap: () => onTileSelected(tiles[i]),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: cellWidth,
                height: cellHeight,
                // The tile art carries its own face and edge; only the
                // current tile gets a frame.
                decoration: tiles[i] == currentTile
                    ? BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.small),
                        border: Border.all(color: scheme.primary, width: 1.5),
                      )
                    : null,
                alignment: Alignment.center,
                child: _tileImage(tiles[i]),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tileImage(String tile) {
    final path = tileAssetPath(tile);
    if (path == null) return const SizedBox.shrink();
    return Image.asset(path, fit: BoxFit.contain);
  }
}
