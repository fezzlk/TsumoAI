import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A hand's manually entered bonus count, independent of tile observations.
class NorthCountCounter extends StatelessWidget {
  const NorthCountCounter({
    super.key,
    required this.value,
    required this.onChanged,
  }) : assert(value >= 0 && value <= 4);

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text('抜き北', style: Theme.of(context).textTheme.titleSmall),
      ),
      IconButton(
        key: const ValueKey('north-count-minus'),
        tooltip: '抜き北を1枚減らす',
        onPressed: value > 0 ? () => onChanged(value - 1) : null,
        icon: const Icon(Icons.remove),
      ),
      SizedBox(
        width: AppSizes.tapTarget,
        child: Semantics(
          liveRegion: true,
          excludeSemantics: true,
          label: '抜き北$value枚',
          child: Text(
            '$value枚',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ),
      IconButton(
        key: const ValueKey('north-count-plus'),
        tooltip: '抜き北を1枚増やす',
        onPressed: value < 4 ? () => onChanged(value + 1) : null,
        icon: const Icon(Icons.add),
      ),
    ],
  );
}
