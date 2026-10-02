import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

import '../models/scan_purpose.dart';
import '../services/purpose_switch.dart';
import 'tile_glyph.dart';

/// 「別の確認へ」: picks another purpose for the same confirmed tiles in one
/// tap. Each choice says up front whether the tiles are reused as-is or one
/// tile has to be left out / added, so the follow-up step is not a surprise.
Future<ScanPurpose?> showPurposeSwitchDialog(
  BuildContext context, {
  required ScanPurpose current,
}) {
  return showDialog<ScanPurpose>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Row(
        children: [
          const Expanded(child: Text('別の確認へ')),
          CloseButton(onPressed: () => Navigator.pop(dialogContext)),
        ],
      ),
      children: [
        for (final purpose in ScanPurpose.values)
          if (purpose != current)
            SimpleDialogOption(
              key: ValueKey('switch-purpose-${purpose.name}'),
              onPressed: () => Navigator.pop(dialogContext, purpose),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      purpose.label,
                      style: Theme.of(dialogContext).textTheme.titleMedium,
                    ),
                    Text(switch (purposeSwitchAdjustment(current, purpose)) {
                      PurposeSwitchAdjustment.none => '同じ牌で確認します',
                      PurposeSwitchAdjustment.removeOne => '外す牌を1枚選びます',
                      PurposeSwitchAdjustment.addOne => 'ツモ牌を1枚追加します',
                    }, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
      ],
    ),
  );
}

/// 14 → 13 tiles: shows the concealed tiles ([candidates], slot index →
/// tile code) and returns the slot index the user taps. [highlightedIndex]
/// marks the current あがり牌, the most common tile to leave out.
Future<int?> showTileRemovalDialog(
  BuildContext context, {
  required ScanPurpose target,
  required List<(int, String)> candidates,
  int? highlightedIndex,
}) {
  return showDialog<int>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('外す牌を選択')),
          CloseButton(onPressed: () => Navigator.pop(dialogContext)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${target.label}は${target.defaultTileCount}枚で行います。外す牌をタップしてください。',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (index, tile) in candidates)
                  InkWell(
                    key: ValueKey('remove-tile-$index'),
                    onTap: () => Navigator.pop(dialogContext, index),
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    child: Container(
                      width: 40,
                      height: 52,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: index == highlightedIndex
                              ? dialogContext.appColors.winningTile
                              : Colors.transparent,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.small),
                      ),
                      child: TileGlyph(tileCode: tile),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
