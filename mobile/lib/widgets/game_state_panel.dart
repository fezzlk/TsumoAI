import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../models/score_request.dart';
import 'tile_glyph.dart';
import 'tile_image_picker.dart';

/// Facts about the current hand/round — 場風・自風・ドラ表示牌・裏ドラ表示牌・
/// 本場・供託 — as opposed to win-time scoring conditions (riichi, ippatsu,
/// haitei, ...), which live in `ContextInputPanel`'s "詳細条件" sheet
/// instead. This panel sits on the main results screen alongside the other
/// table-state input (photo, tile thumbnails, melds).
class GameStatePanel extends StatelessWidget {
  final ContextInput context_;
  final ValueChanged<ContextInput> onChanged;

  const GameStatePanel({
    super.key,
    required this.context_,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _windSelector(
                context,
                '場風',
                context_.roundWind,
                (v) => onChanged(context_.copyWith(roundWind: v)),
              ),
              _windSelector(
                context,
                '自風',
                context_.seatWind,
                (v) => onChanged(
                  context_.copyWith(seatWind: v, isDealer: v == 'E'),
                ),
              ),
              SizedBox(
                width: 210,
                child: _indicatorRow(
                  context,
                  'ドラ表示牌',
                  context_.doraIndicators,
                  (list) => onChanged(context_.copyWith(doraIndicators: list)),
                ),
              ),
              // Always visible (not just when riichi is set) — 裏ドラ表示牌
              // is a table fact from the photo like ドラ表示牌 itself, so it
              // sits in the same row rather than appearing/disappearing
              // based on a different field.
              SizedBox(
                width: 210,
                child: _indicatorRow(
                  context,
                  '裏ドラ表示牌',
                  context_.uraDoraIndicators,
                  (list) =>
                      onChanged(context_.copyWith(uraDoraIndicators: list)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _windSelector(
    BuildContext context,
    String label,
    String value,
    ValueChanged<String> onValueChanged,
  ) {
    const winds = ['E', 'S', 'W', 'N'];
    const windLabels = {'E': '東', 'S': '南', 'W': '西', 'N': '北'};
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 4),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: InkWell(
            key: ValueKey('wind-selector-$label'),
            borderRadius: BorderRadius.circular(AppRadius.medium),
            onTap: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Row(
                  children: [
                    Expanded(child: Text('$labelを選択')),
                    const CloseButton(),
                  ],
                ),
                content: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final wind in winds)
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: wind == value
                            ? FilledButton(
                                key: ValueKey('$label-$wind'),
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                  onValueChanged(wind);
                                },
                                child: Text(windLabels[wind]!),
                              )
                            : OutlinedButton(
                                key: ValueKey('$label-$wind'),
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                  onValueChanged(wind);
                                },
                                child: Text(windLabels[wind]!),
                              ),
                      ),
                  ],
                ),
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              child: Center(
                child: Text(
                  windLabels[value] ?? value,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _indicatorRow(
    BuildContext context,
    String label,
    List<String> indicators,
    ValueChanged<List<String>> onListChanged,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 6),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (int i = 0; i < indicators.length; i++)
                GestureDetector(
                  onTap: () {
                    final next = [...indicators]..removeAt(i);
                    onListChanged(next);
                  },
                  child: Container(
                    width: 26,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppRadius.small),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: TileGlyph(
                              tileCode: indicators[i],
                              fallbackTextStyle: Theme.of(
                                context,
                              ).textTheme.labelSmall,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Icon(
                            Icons.close,
                            size: 10,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              GestureDetector(
                onTap: () async {
                  final tile = await TileImagePicker.show(context);
                  if (tile != null) onListChanged([...indicators, tile]);
                },
                child: Container(
                  width: 26,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.add,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
