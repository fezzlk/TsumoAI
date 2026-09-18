import 'package:flutter/material.dart';
import '../models/score_request.dart';

/// Win-time scoring conditions — ツモ/ロン, リーチ・一発, and the rare
/// situational flags (海底・河底・嶺上・槍槓・地和・天和). Facts about the
/// current round that aren't tied to winning (場風・自風・ドラ表示牌・本場・
/// 供託) live in `GameStatePanel` on the main results screen instead.
class ContextInputPanel extends StatefulWidget {
  final ContextInput context_;
  final ValueChanged<ContextInput> onChanged;

  const ContextInputPanel({
    super.key,
    required this.context_,
    required this.onChanged,
  });

  @override
  State<ContextInputPanel> createState() => _ContextInputPanelState();
}

class _ContextInputPanelState extends State<ContextInputPanel> {
  bool _expanded = false;

  ContextInput get _ctx => widget.context_;
  void _update(ContextInput c) => widget.onChanged(c);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Win type + Riichi + Ippatsu
          Row(
            children: [
              _winTypeToggle(),
              const SizedBox(width: 12),
              _riichiSelector(),
              if (_ctx.riichi || _ctx.doubleRiichi) ...[
                const SizedBox(width: 8),
                _chip('一発', _ctx.ippatsu, (v) => _update(_ctx.copyWith(ippatsu: v))),
              ],
              const Spacer(),
              // Expand/collapse button
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded ? '詳細を閉じる' : '詳細オプション',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.white38, size: 16,
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Expanded: rare situational flags
          if (_expanded) ...[
            const SizedBox(height: 6),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 6),

            // Row 2: Haitei, Houtei, Rinshan, Chankan, Chiihou, Tenhou
            Wrap(
              spacing: 6, runSpacing: 4,
              children: [
                _chip('海底', _ctx.haitei, (v) => _update(_ctx.copyWith(haitei: v))),
                _chip('河底', _ctx.houtei, (v) => _update(_ctx.copyWith(houtei: v))),
                _chip('嶺上', _ctx.rinshan, (v) => _update(_ctx.copyWith(rinshan: v))),
                _chip('槍槓', _ctx.chankan, (v) => _update(_ctx.copyWith(chankan: v))),
                _chip('地和', _ctx.chiihou, (v) => _update(_ctx.copyWith(chiihou: v))),
                _chip('天和', _ctx.tenhou, (v) => _update(_ctx.copyWith(tenhou: v))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _winTypeToggle() {
    final isTsumo = _ctx.winType == 'tsumo';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chipButton('ツモ', isTsumo, () => _update(_ctx.copyWith(winType: 'tsumo'))),
        const SizedBox(width: 4),
        _chipButton('ロン', !isTsumo, () => _update(_ctx.copyWith(winType: 'ron'))),
      ],
    );
  }

  Widget _riichiSelector() {
    final isNone = !_ctx.riichi && !_ctx.doubleRiichi;
    final isRiichi = _ctx.riichi && !_ctx.doubleRiichi;
    final isDouble = _ctx.doubleRiichi;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _chipButton('なし', isNone, () =>
            _update(_ctx.copyWith(riichi: false, doubleRiichi: false, ippatsu: false))),
        const SizedBox(width: 3),
        _chipButton('リーチ', isRiichi, () =>
            _update(_ctx.copyWith(riichi: true, doubleRiichi: false))),
        const SizedBox(width: 3),
        _chipButton('Wリーチ', isDouble, () =>
            _update(_ctx.copyWith(riichi: true, doubleRiichi: true))),
      ],
    );
  }

  Widget _chipButton(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.green.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: selected ? Border.all(color: Colors.greenAccent, width: 1) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.greenAccent : Colors.white54,
            fontSize: 11, fontWeight: FontWeight.bold,
          ),
        ),
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
