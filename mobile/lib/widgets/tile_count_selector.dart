import 'package:flutter/material.dart';

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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '想定牌数',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final count in options)
                _CountButton(
                  count: count,
                  selected: count == selectedCount,
                  onPressed: () => onChanged(count),
                ),
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
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? '牌数を自動推定' : '想定牌数$count枚',
      child: SizedBox(
        height: 44,
        child: Material(
          color: selected
              ? Colors.green.shade700.withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: count == null ? 54 : 40),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
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
