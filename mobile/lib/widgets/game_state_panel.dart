import 'package:flutter/material.dart';
import '../models/score_request.dart';
import 'tile_glyph.dart';
import 'tile_image_picker.dart';

/// Facts about the current hand/round — 場風・自風・ドラ表示牌・裏ドラ表示牌・
/// 本場・供託 — as opposed to win-time scoring conditions (riichi, ippatsu,
/// haitei, ...), which live in `ContextInputPanel`'s "詳細条件" sheet
/// instead. This panel sits on the main results screen alongside the other
/// table-state input (photo, tile thumbnails, melds).
class GameStatePanel extends StatelessWidget {
  final ContextInput context_;
  final ValueChanged<ContextInput> onChanged;

  const GameStatePanel({
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _windSelector(
                '場風',
                context_.roundWind,
                (v) => onChanged(context_.copyWith(roundWind: v)),
              ),
              const SizedBox(width: 8),
              _windSelector(
                '自風',
                context_.seatWind,
                (v) => onChanged(
                  context_.copyWith(seatWind: v, isDealer: v == 'E'),
                ),
              ),
              const SizedBox(width: 16),
              _numberInput(
                '本場',
                context_.honba,
                (v) => onChanged(context_.copyWith(honba: v)),
              ),
              const SizedBox(width: 12),
              _numberInput(
                '供託',
                context_.kyotaku,
                (v) => onChanged(context_.copyWith(kyotaku: v)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _indicatorRow(
                  context,
                  'ドラ表示牌',
                  context_.doraIndicators,
                  (list) => onChanged(context_.copyWith(doraIndicators: list)),
                ),
              ),
              const SizedBox(width: 12),
              // Always visible (not just when riichi is set) — 裏ドラ表示牌
              // is a table fact from the photo like ドラ表示牌 itself, so it
              // sits in the same row rather than appearing/disappearing
              // based on a different field.
              Expanded(
                child: _indicatorRow(
                  context,
                  '裏ドラ表示牌',
                  context_.uraDoraIndicators,
                  (list) => onChanged(context_.copyWith(uraDoraIndicators: list)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _windSelector(
    String label,
    String value,
    ValueChanged<String> onValueChanged,
  ) {
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
              value: value,
              isDense: true,
              dropdownColor: Colors.grey[850],
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: winds
                  .map(
                    (w) => DropdownMenuItem(
                      value: w,
                      child: Text(windLabels[w]!),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) onValueChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _numberInput(
    String label,
    int value,
    ValueChanged<int> onValueChanged,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () {
            if (value > 0) onValueChanged(value - 1);
          },
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: const Text('-', style: TextStyle(color: Colors.white54, fontSize: 14)),
          ),
        ),
        Container(
          width: 28,
          height: 24,
          alignment: Alignment.center,
          child: Text('$value', style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
        GestureDetector(
          onTap: () => onValueChanged(value + 1),
          child: Container(
            width: 24,
            height: 24,
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

  Widget _indicatorRow(
    BuildContext context,
    String label,
    List<String> indicators,
    ValueChanged<List<String>> onListChanged,
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
                    onListChanged(next);
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
                              fallbackTextStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
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
                  if (tile != null) onListChanged([...indicators, tile]);
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
}
