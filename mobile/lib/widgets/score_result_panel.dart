import 'package:flutter/material.dart';
import '../models/score_result.dart';

/// Panel displaying the score calculation result.
class ScoreResultPanel extends StatelessWidget {
  final ScoreResponse scoreResponse;

  const ScoreResultPanel({super.key, required this.scoreResponse});

  @override
  Widget build(BuildContext context) {
    final r = scoreResponse.result;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Point label
          Text(
            r.pointLabel,
            style: const TextStyle(
              color: Colors.amberAccent, fontSize: 22, fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          // Han / Fu
          Text(
            '${r.han}飜 ${r.fu}符',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 4),
          _buildPoints(r),
          const SizedBox(height: 8),
          // Yaku chips
          Wrap(
            spacing: 4, runSpacing: 4,
            children: r.yaku.map((y) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${y.name} ${y.han}飜',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            )).toList(),
          ),
          // Fu breakdown
          if (r.fuBreakdown.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '符内訳: ${r.fuBreakdown.map((f) => '${f.name}${f.fu}').join(' + ')}',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPoints(ScoreResult r) {
    final pts = r.points;
    if (pts.ron > 0) {
      return Text('ロン: ${pts.ron}点',
          style: const TextStyle(color: Colors.white, fontSize: 15));
    }
    if (pts.tsumoDealerPay > 0 || pts.tsumoNonDealerPay > 0) {
      if (pts.tsumoDealerPay == pts.tsumoNonDealerPay) {
        return Text('ツモ: ${pts.tsumoNonDealerPay}点 オール',
            style: const TextStyle(color: Colors.white, fontSize: 15));
      }
      return Text('ツモ: ${pts.tsumoNonDealerPay} / ${pts.tsumoDealerPay}点',
          style: const TextStyle(color: Colors.white, fontSize: 15));
    }
    return const SizedBox.shrink();
  }
}
