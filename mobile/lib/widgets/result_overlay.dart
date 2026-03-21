import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../models/score_result.dart';
import '../models/recognize_result.dart';
import '../screens/feedback_screen.dart';

class ResultOverlay extends StatelessWidget {
  final RecognizeResponse recognition;
  final ScoreResponse? score;
  final bool isNotWinning;

  const ResultOverlay({
    super.key,
    required this.recognition,
    this.score,
    this.isNotWinning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.85),
              Colors.black.withValues(alpha: 0.0),
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTilesRow(),
            const SizedBox(height: 12),
            if (isNotWinning) _buildNotWinningSection(),
            if (score != null) _buildScoreSection(score!),
            const SizedBox(height: 10),
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTilesRow() {
    final tiles = recognition.handEstimate.topTiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '認識結果',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: tiles.map((tile) => _tileBadge(tile)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _tileBadge(String tile) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tile,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildNotWinningSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '上がりの形になっていません',
              style: TextStyle(
                color: Colors.redAccent,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreSection(ScoreResponse scoreResp) {
    final r = scoreResp.result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Point label (e.g. "満貫", "跳満")
        Text(
          r.pointLabel,
          style: const TextStyle(
            color: Colors.amberAccent,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        // Han / Fu
        Text(
          '${r.han}飜 ${r.fu}符',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        // Points
        _buildPointsText(r),
        const SizedBox(height: 8),
        // Yaku list
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: r.yaku
              .map((y) => Chip(
                    label: Text('${y.name} (${y.han}飜)'),
                    labelStyle: const TextStyle(fontSize: 11),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.white24,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildPointsText(ScoreResult r) {
    final pts = r.points;
    if (pts.ron > 0) {
      return Text(
        'ロン: ${pts.ron}点',
        style: const TextStyle(color: Colors.white, fontSize: 16),
      );
    }
    if (pts.tsumoDealerPay > 0 || pts.tsumoNonDealerPay > 0) {
      if (pts.tsumoDealerPay == pts.tsumoNonDealerPay) {
        return Text(
          'ツモ: ${pts.tsumoNonDealerPay}点 オール',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        );
      }
      return Text(
        'ツモ: ${pts.tsumoNonDealerPay} / ${pts.tsumoDealerPay}点',
        style: const TextStyle(color: Colors.white, fontSize: 16),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildActionButtons(BuildContext context) {
    final tiles = recognition.handEstimate.topTiles;
    final tilesParam = tiles.join(',');
    final url = '${AppConfig.apiBaseUrl}/score-ui?tiles=$tilesParam';

    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: Colors.white.withValues(alpha: 0.15),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
      ),
    );

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('WEBで牌姿を修正'),
            style: buttonStyle,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FeedbackScreen(
                    recognition: recognition,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.feedback_outlined, size: 18),
            label: const Text('認識が違う（フィードバック）'),
            style: buttonStyle,
          ),
        ),
      ],
    );
  }
}
