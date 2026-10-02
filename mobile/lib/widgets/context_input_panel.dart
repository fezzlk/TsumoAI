import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'toggle_chip.dart';
import '../models/score_request.dart';

/// The rare situational win-time flags — 海底・河底・嶺上・槍槓・地和・天和.
/// リーチ・一発 (used on many hands) live directly in `ScanScreen`'s bottom
/// action bar instead (`_buildQuickWinConditions`) so
/// they don't need an extra tap through this "詳細条件" sheet; only the
/// flags rare enough that a sheet tap is an acceptable cost stay here.
/// Facts about the current round that aren't tied to winning (場風・自風・
/// ドラ表示牌・本場・供託) live in `GameStatePanel` on the main results
/// screen instead.
class ContextInputPanel extends StatelessWidget {
  final ContextInput context_;
  final ValueChanged<ContextInput> onChanged;

  const ContextInputPanel({
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
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          _chip(
            '海底',
            context_.haitei,
            (v) => onChanged(context_.copyWith(haitei: v)),
          ),
          _chip(
            '河底',
            context_.houtei,
            (v) => onChanged(context_.copyWith(houtei: v)),
          ),
          _chip(
            '嶺上',
            context_.rinshan,
            (v) => onChanged(context_.copyWith(rinshan: v)),
          ),
          _chip(
            '槍槓',
            context_.chankan,
            (v) => onChanged(context_.copyWith(chankan: v)),
          ),
          _chip(
            '地和',
            context_.chiihou,
            (v) => onChanged(context_.copyWith(chiihou: v)),
          ),
          _chip(
            '天和',
            context_.tenhou,
            (v) => onChanged(context_.copyWith(tenhou: v)),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool value, ValueChanged<bool> onChanged) =>
      ToggleChip(label: label, selected: value, onTap: () => onChanged(!value));
}
