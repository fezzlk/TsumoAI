import 'package:flutter/material.dart';
import '../models/score_request.dart';

/// The rare situational win-time flags — 海底・河底・嶺上・槍槓・地和・天和.
/// ツモ/ロン and リーチ・一発 (used on nearly every hand) live directly in
/// `ScanScreen`'s bottom action bar instead (`_buildQuickWinConditions`) so
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
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          _chip('海底', context_.haitei, (v) => onChanged(context_.copyWith(haitei: v))),
          _chip('河底', context_.houtei, (v) => onChanged(context_.copyWith(houtei: v))),
          _chip('嶺上', context_.rinshan, (v) => onChanged(context_.copyWith(rinshan: v))),
          _chip('槍槓', context_.chankan, (v) => onChanged(context_.copyWith(chankan: v))),
          _chip('地和', context_.chiihou, (v) => onChanged(context_.copyWith(chiihou: v))),
          _chip('天和', context_.tenhou, (v) => onChanged(context_.copyWith(tenhou: v))),
        ],
      ),
    );
  }

  Widget _chip(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: value ? Colors.green.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: value ? Border.all(color: Colors.greenAccent, width: 1) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: value ? Colors.greenAccent : Colors.white54,
            fontSize: 11, fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
