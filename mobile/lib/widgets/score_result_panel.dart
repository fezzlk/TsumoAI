import 'package:flutter/material.dart';

import '../models/score_result.dart';

/// Displays the same confirmed hand as both a tsumo and ron result.
class ScoreResultPanel extends StatelessWidget {
  const ScoreResultPanel({
    super.key,
    required this.tsumoResponse,
    required this.ronResponse,
  });

  final ScoreResponse? tsumoResponse;
  final ScoreResponse? ronResponse;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _resultSection('ツモの場合', tsumoResponse?.result),
          const Divider(color: Colors.white24, height: 24),
          _resultSection('ロンの場合', ronResponse?.result),
        ],
      ),
    );
  }

  Widget _resultSection(String label, ScoreResult? result) {
    if (result == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'この条件では和了として成立しません',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          result.pointLabel,
          style: const TextStyle(
            color: Colors.amberAccent,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${result.han}飜 ${result.fu}符',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 4),
        _buildPoints(result),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: result.yaku
              .map(
                (y) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${y.name} ${y.han}飜',
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              )
              .toList(),
        ),
        if (result.fuBreakdown.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '符内訳: ${result.fuBreakdown.map((f) => '${f.name}${f.fu}').join(' + ')}',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ],
    );
  }

  Widget _buildPoints(ScoreResult result) {
    final points = result.points;
    if (points.ron > 0) {
      return Text(
        'ロン: ${points.ron}点',
        style: const TextStyle(color: Colors.white, fontSize: 15),
      );
    }
    if (points.tsumoDealerPay > 0 || points.tsumoNonDealerPay > 0) {
      if (points.tsumoDealerPay == points.tsumoNonDealerPay) {
        return Text(
          'ツモ: ${points.tsumoNonDealerPay}点 オール',
          style: const TextStyle(color: Colors.white, fontSize: 15),
        );
      }
      return Text(
        'ツモ: ${points.tsumoNonDealerPay} / ${points.tsumoDealerPay}点',
        style: const TextStyle(color: Colors.white, fontSize: 15),
      );
    }
    return const SizedBox.shrink();
  }
}
