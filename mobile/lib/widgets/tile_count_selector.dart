import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 自動・13〜18 tile-count choice. Large white chips with the selection
/// filled green; 17 and 18 are rare, so they sit past the right edge and
/// are reached by scrolling (decided 2026-09-26).
class TileCountSelector extends StatelessWidget {
  const TileCountSelector({
    super.key,
    required this.selectedCount,
    required this.counts,
    required this.onChanged,
    this.includeAuto = true,
    this.labelOf,
    this.semanticsOf,
  });

  final int? selectedCount;
  final List<int> counts;
  final ValueChanged<int?> onChanged;

  /// Whether the leading 自動 chip is offered.
  final bool includeAuto;

  /// Chip text for a count (defaults to the count itself).
  final String Function(int count)? labelOf;

  /// Spoken label for a count (defaults to 想定牌数N枚).
  final String Function(int count)? semanticsOf;

  @override
  Widget build(BuildContext context) {
    final options = <int?>[if (includeAuto) null, ...counts];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Clipped to the card's inner edge; the vertical padding keeps the
      // selected chip's shadow from being cut.
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          for (var index = 0; index < options.length; index++) ...[
            if (index > 0) const SizedBox(width: AppSpacing.s),
            _CountButton(
              count: options[index],
              label: options[index] == null
                  ? '自動'
                  : labelOf?.call(options[index]!) ?? '${options[index]}',
              semantics: options[index] == null
                  ? '牌数を自動推定'
                  : semanticsOf?.call(options[index]!) ??
                        '想定牌数${options[index]}枚',
              selected: options[index] == selectedCount,
              onPressed: () => onChanged(options[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _CountButton extends StatelessWidget {
  const _CountButton({
    required this.count,
    required this.label,
    required this.semantics,
    required this.selected,
    required this.onPressed,
  });

  final int? count;
  final String label;
  final String semantics;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: semantics,
      child: SizedBox(
        width: count == null ? 88 : 60,
        height: AppSizes.primaryButton,
        child: Material(
          color: selected ? scheme.primary : scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          elevation: selected ? 2 : 0,
          shadowColor: scheme.primary.withValues(alpha: 0.3),
          child: InkWell(
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            onTap: onPressed,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: selected ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
