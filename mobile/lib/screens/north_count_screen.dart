import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/screen_header.dart';

/// Explicit per-winner count selection before a three-player win is scored.
class NorthCountScreen extends StatelessWidget {
  const NorthCountScreen({super.key, this.initialCount = 0})
    : assert(initialCount >= 0 && initialCount <= 4);

  final int initialCount;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          const ScreenHeader(title: '北抜き回数'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.l),
              children: [
                Text(
                  '和了者が抜いた北は何枚ですか？',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.m),
                for (var count = 0; count <= 4; count++) ...[
                  Semantics(
                    selected: count == initialCount,
                    child: OutlinedButton(
                      key: ValueKey('north-count-choice-$count'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(64),
                      ),
                      onPressed: () => Navigator.pop(context, count),
                      child: Text(count == 0 ? '0枚（北抜きなし）' : '$count枚'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.m),
                ],
                const Text('枚数はドラ入力欄でも変更できます。'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
