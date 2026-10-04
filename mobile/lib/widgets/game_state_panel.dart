import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../models/score_request.dart';
import 'tile_glyph.dart';
import 'tile_image_picker.dart';

/// Condition card of the results screen: 場風・自風 pills followed by the
/// caller's win-condition chips (立直・一発・海底 …) in one horizontally
/// scrolling row, then the 表ドラ / 裏ドラ indicator fields side by side
/// (decided 2026-09-26: chips sit in the wind row and scroll sideways).
class GameStatePanel extends StatelessWidget {
  final ContextInput context_;
  final ValueChanged<ContextInput> onChanged;

  /// Win-time condition chips shown after the wind pills (score only).
  final List<Widget> conditionChips;

  /// Whether the 裏ドラ field is shown next to 表ドラ. Only scoring uses
  /// 裏ドラ; the other checks take 表ドラ alone (decided 2026-10-04).
  final bool showUraDora;

  const GameStatePanel({
    super.key,
    required this.context_,
    required this.onChanged,
    this.conditionChips = const [],
    this.showUraDora = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pills = <Widget>[
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
        (v) => onChanged(context_.copyWith(seatWind: v, isDealer: v == 'E')),
      ),
      ...conditionChips,
    ];
    final pillRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < pills.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            pills[i],
          ],
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          pillRow,
          const SizedBox(height: AppSpacing.s),
          // When shown, 裏ドラ is there regardless of riichi: it is a table
          // fact from the photo like ドラ表示牌 itself.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _indicatorField(
                    context,
                    '表ドラ表示牌',
                    context_.doraIndicators,
                    (list) =>
                        onChanged(context_.copyWith(doraIndicators: list)),
                  ),
                ),
                if (showUraDora) ...[
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: _indicatorField(
                      context,
                      '裏ドラ表示牌',
                      context_.uraDoraIndicators,
                      (list) =>
                          onChanged(context_.copyWith(uraDoraIndicators: list)),
                    ),
                  ),
                ],
              ],
            ),
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
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        key: ValueKey('wind-selector-$label'),
        borderRadius: BorderRadius.circular(AppRadius.chip),
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
          constraints: const BoxConstraints(minHeight: AppSizes.chip),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: text.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Text(windLabels[value] ?? value, style: text.titleSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _indicatorField(
    BuildContext context,
    String label,
    List<String> indicators,
    ValueChanged<List<String>> onListChanged,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget tileBox({required Widget child, VoidCallback? onTap, String? tip}) {
      final box = GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.small),
            border: Border.all(color: scheme.outline),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      );
      return tip == null ? box : Tooltip(message: tip, child: box);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.s,
        AppSpacing.s,
        AppSpacing.s,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      child: Row(
        children: [
          Flexible(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 1,
                style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            flex: 3,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                for (int i = 0; i < indicators.length; i++)
                  tileBox(
                    tip: '$labelを外す',
                    onTap: () => onListChanged([...indicators]..removeAt(i)),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: TileGlyph(
                        tileCode: indicators[i],
                        fallbackTextStyle: text.labelSmall,
                      ),
                    ),
                  ),
                tileBox(
                  tip: '$labelを追加',
                  onTap: () async {
                    final tile = await TileImagePicker.show(context);
                    if (tile != null) onListChanged([...indicators, tile]);
                  },
                  child: Icon(Icons.add, size: 16, color: scheme.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
