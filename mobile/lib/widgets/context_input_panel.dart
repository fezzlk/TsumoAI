import 'package:flutter/material.dart';
import '../models/score_request.dart';
import 'tile_glyph.dart';
import 'tile_image_picker.dart';

/// Compact panel for game context input.
/// Basic options always visible; advanced options in expandable section.
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
          // Row 1: Winds + Win type
          Row(
            children: [
              _windSelector('場風', _ctx.roundWind, (v) =>
                  _update(_ctx.copyWith(roundWind: v))),
              const SizedBox(width: 8),
              _windSelector('自風', _ctx.seatWind, (v) =>
                  _update(_ctx.copyWith(seatWind: v, isDealer: v == 'E'))),
              const SizedBox(width: 12),
              _winTypeToggle(),
            ],
          ),
          const SizedBox(height: 6),

          // Row 2: Riichi + Ippatsu
          Row(
            children: [
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

          // Expanded: advanced options
          if (_expanded) ...[
            const SizedBox(height: 6),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 6),

            // Row 3: Haitei, Houtei, Rinshan, Chankan
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
            const SizedBox(height: 8),

            // ドラ表示牌 (always relevant) / 裏ドラ表示牌 (only meaningful
            // under riichi, so only shown then). Aka-dora is NOT entered
            // here — it's counted automatically from the actual recognized
            // hand tiles (see scan_screen.dart's `_confirmAndAnalyze`),
            // since the app already knows which tiles are red fives.
            _doraIndicatorRow(
              'ドラ表示牌',
              _ctx.doraIndicators,
              (list) => _update(_ctx.copyWith(doraIndicators: list)),
            ),
            if (_ctx.riichi || _ctx.doubleRiichi) ...[
              const SizedBox(height: 6),
              _doraIndicatorRow(
                '裏ドラ表示牌',
                _ctx.uraDoraIndicators,
                (list) => _update(_ctx.copyWith(uraDoraIndicators: list)),
              ),
            ],
            const SizedBox(height: 8),

            // Row 4: Honba, Kyotaku
            Row(
              children: [
                _numberInput('本場', _ctx.honba, (v) => _update(_ctx.copyWith(honba: v))),
                const SizedBox(width: 12),
                _numberInput('供託', _ctx.kyotaku, (v) => _update(_ctx.copyWith(kyotaku: v))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _windSelector(String label, String value, ValueChanged<String> onChanged) {
    const winds = ['E', 'S', 'W', 'N'];
    const windLabels = {'E': '東', 'S': '南', 'W': '西', 'N': '北'};
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(width: 4),
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value, isDense: true,
              dropdownColor: Colors.grey[850],
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: winds.map((w) => DropdownMenuItem(value: w, child: Text(windLabels[w]!))).toList(),
              onChanged: (v) { if (v != null) onChanged(v); },
            ),
          ),
        ),
      ],
    );
  }

  Widget _winTypeToggle() {
    final isTsumo = _ctx.winType == 'tsumo';
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _chipButton('ツモ', isTsumo, () => _update(_ctx.copyWith(winType: 'tsumo'))),
          const SizedBox(width: 4),
          _chipButton('ロン', !isTsumo, () => _update(_ctx.copyWith(winType: 'ron'))),
        ],
      ),
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

  Widget _doraIndicatorRow(
    String label,
    List<String> indicators,
    ValueChanged<List<String>> onChanged,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
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
                    onChanged(next);
                  },
                  child: Container(
                    width: 26,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: TileGlyph(
                              tileCode: indicators[i],
                              fallbackTextStyle: const TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ),
                        const Positioned(
                          right: 0,
                          top: 0,
                          child: Icon(Icons.close, size: 10, color: Colors.redAccent),
                        ),
                      ],
                    ),
                  ),
                ),
              GestureDetector(
                onTap: () async {
                  final tile = await TileImagePicker.show(context);
                  if (tile != null) onChanged([...indicators, tile]);
                },
                child: Container(
                  width: 26,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24, style: BorderStyle.solid),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.add, size: 16, color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _numberInput(String label, int value, ValueChanged<int> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () { if (value > 0) onChanged(value - 1); },
          child: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: const Text('-', style: TextStyle(color: Colors.white54, fontSize: 14)),
          ),
        ),
        Container(
          width: 28, height: 24,
          alignment: Alignment.center,
          child: Text('$value', style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
        GestureDetector(
          onTap: () => onChanged(value + 1),
          child: Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: const Text('+', style: TextStyle(color: Colors.white54, fontSize: 14)),
          ),
        ),
      ],
    );
  }
}
