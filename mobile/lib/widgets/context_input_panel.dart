import 'package:flutter/material.dart';
import '../models/score_request.dart';

/// Compact panel for entering game context (wind, riichi, tsumo/ron, etc.)
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
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Winds + Win type
          Row(
            children: [
              _windSelector('場風', context_.roundWind, (v) {
                onChanged(ContextInput(
                  winType: context_.winType, isDealer: context_.isDealer,
                  roundWind: v, seatWind: context_.seatWind,
                  riichi: context_.riichi, ippatsu: context_.ippatsu,
                  haitei: context_.haitei, houtei: context_.houtei,
                  rinshan: context_.rinshan, chankan: context_.chankan,
                ));
              }),
              const SizedBox(width: 8),
              _windSelector('自風', context_.seatWind, (v) {
                onChanged(ContextInput(
                  winType: context_.winType, isDealer: v == 'E',
                  roundWind: context_.roundWind, seatWind: v,
                  riichi: context_.riichi, ippatsu: context_.ippatsu,
                  haitei: context_.haitei, houtei: context_.houtei,
                  rinshan: context_.rinshan, chankan: context_.chankan,
                ));
              }),
              const SizedBox(width: 12),
              _winTypeToggle(),
            ],
          ),
          const SizedBox(height: 6),
          // Row 2: Riichi + Ippatsu
          Row(
            children: [
              _toggle('リーチ', context_.riichi, (v) {
                onChanged(ContextInput(
                  winType: context_.winType, isDealer: context_.isDealer,
                  roundWind: context_.roundWind, seatWind: context_.seatWind,
                  riichi: v, ippatsu: v ? context_.ippatsu : false,
                  haitei: context_.haitei, houtei: context_.houtei,
                  rinshan: context_.rinshan, chankan: context_.chankan,
                ));
              }),
              const SizedBox(width: 8),
              if (context_.riichi)
                _toggle('一発', context_.ippatsu, (v) {
                  onChanged(ContextInput(
                    winType: context_.winType, isDealer: context_.isDealer,
                    roundWind: context_.roundWind, seatWind: context_.seatWind,
                    riichi: context_.riichi, ippatsu: v,
                    haitei: context_.haitei, houtei: context_.houtei,
                    rinshan: context_.rinshan, chankan: context_.chankan,
                  ));
                }),
            ],
          ),
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
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              dropdownColor: Colors.grey[850],
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: winds.map((w) => DropdownMenuItem(
                value: w,
                child: Text(windLabels[w]!),
              )).toList(),
              onChanged: (v) { if (v != null) onChanged(v); },
            ),
          ),
        ),
      ],
    );
  }

  Widget _winTypeToggle() {
    final isTsumo = context_.winType == 'tsumo';
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _chipButton('ツモ', isTsumo, () {
            onChanged(ContextInput(
              winType: 'tsumo', isDealer: context_.isDealer,
              roundWind: context_.roundWind, seatWind: context_.seatWind,
              riichi: context_.riichi, ippatsu: context_.ippatsu,
              haitei: context_.haitei, houtei: context_.houtei,
              rinshan: context_.rinshan, chankan: context_.chankan,
            ));
          }),
          const SizedBox(width: 4),
          _chipButton('ロン', !isTsumo, () {
            onChanged(ContextInput(
              winType: 'ron', isDealer: context_.isDealer,
              roundWind: context_.roundWind, seatWind: context_.seatWind,
              riichi: context_.riichi, ippatsu: context_.ippatsu,
              haitei: context_.haitei, houtei: context_.houtei,
              rinshan: context_.rinshan, chankan: context_.chankan,
            ));
          }),
        ],
      ),
    );
  }

  Widget _chipButton(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.green.withOpacity(0.5) : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: selected ? Border.all(color: Colors.greenAccent, width: 1) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.greenAccent : Colors.white54,
            fontSize: 13, fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: value ? Colors.green.withOpacity(0.4) : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: value ? Border.all(color: Colors.greenAccent, width: 1) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: value ? Colors.greenAccent : Colors.white54,
            fontSize: 12, fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
