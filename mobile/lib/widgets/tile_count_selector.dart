import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TileCountSelector extends StatelessWidget {
  const TileCountSelector({
    super.key,
    required this.selectedCount,
    required this.counts,
    required this.onChanged,
  });

  final int? selectedCount;
  final List<int> counts;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <int?>[null, ...counts];
    final scheme = Theme.of(context).colorScheme;
    // Follows the surrounding theme: dark on the camera, light on results.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.large),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('想定牌数', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var index = 0; index < options.length; index++) ...[
                if (index > 0) const SizedBox(width: 3),
                Expanded(
                  child: _CountButton(
                    count: options[index],
                    selected: options[index] == selectedCount,
                    onPressed: () => onChanged(options[index]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CountButton extends StatelessWidget {
  const _CountButton({
    required this.count,
    required this.selected,
    required this.onPressed,
  });

  final int? count;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = count?.toString() ?? '自動';
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? '牌数を自動推定' : '想定牌数$count枚',
      child: SizedBox(
        height: 44,
        child: Material(
          color: selected ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            onTap: onPressed,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: selected ? scheme.onPrimary : scheme.onSurface,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
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
