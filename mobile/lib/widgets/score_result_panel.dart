import 'package:flutter/material.dart';

import '../models/score_result.dart';
import '../models/score_request.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Displays the same confirmed hand as both a tsumo and ron result.
class ScoreResultPanel extends StatelessWidget {
  const ScoreResultPanel({
    super.key,
    required this.tsumoResponse,
    required this.ronResponse,
    this.ruleSettings = const MahjongRuleSettings(),
    this.isOpenHand = false,
  });

  final ScoreResponse? tsumoResponse;
  final ScoreResponse? ronResponse;
  final MahjongRuleSettings ruleSettings;
  final bool isOpenHand;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _resultSection(
              context,
              'ツモの場合',
              tsumoResponse?.result,
              isTsumo: true,
            ),
            const Divider(height: AppSpacing.xl),
            _resultSection(
              context,
              'ロンの場合',
              ronResponse?.result,
              isTsumo: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultSection(
    BuildContext context,
    String label,
    ScoreResult? result, {
    required bool isTsumo,
  }) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (result == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text('この条件では和了として成立しません', style: text.bodySmall),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          result.pointLabel,
          style: text.headlineSmall?.copyWith(
            color: context.appColors.scoreHighlight,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text('${result.han}飜 ${result.fu}符', style: text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        _buildPoints(context, result),
        if (ruleSettings.chipsEnabled) ...[
          const SizedBox(height: AppSpacing.xs),
          _buildChips(context, result, isTsumo: isTsumo),
        ],
        const SizedBox(height: AppSpacing.s),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: result.yaku
              .map(
                (y) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                  ),
                  child: Text(
                    '${y.name} ${y.han}飜',
                    style: text.labelMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        if (result.fuBreakdown.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '符内訳: ${result.fuBreakdown.map((f) => '${f.name}${f.fu}').join(' + ')}',
            style: text.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _buildChips(
    BuildContext context,
    ScoreResult result, {
    required bool isTsumo,
  }) {
    final text = Theme.of(context).textTheme;
    if (isOpenHand && !ruleSettings.openHandChipsEnabled) {
      return Text('チップ: なし（副露あり）', style: text.bodyMedium);
    }
    final red = result.dora.akaDora;
    final ura = result.dora.uraDora;
    final ippatsu = result.yaku.any((item) => item.name == '一発') ? 1 : 0;
    final allStar = red >= 3 ? 2 : 0;
    final chips = red + ura + ippatsu + allStar;
    final equivalent = chips * 1000;
    final payment = isTsumo ? '各$chips枚・合計${chips * 3}枚' : '$chips枚';
    return Text(
      'チップ: $payment（$chipsチップ点 / 素点$equivalent点相当）',
      style: text.bodyMedium?.copyWith(
        color: context.appColors.success.color,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildPoints(BuildContext context, ScoreResult result) {
    final style = Theme.of(context).textTheme.bodyLarge;
    final points = result.points;
    if (points.ron > 0) {
      return Text('ロン: ${points.ron}点', style: style);
    }
    if (points.tsumoDealerPay > 0 || points.tsumoNonDealerPay > 0) {
      if (points.tsumoDealerPay == points.tsumoNonDealerPay) {
        return Text('ツモ: ${points.tsumoNonDealerPay}点 オール', style: style);
      }
      return Text(
        'ツモ: ${points.tsumoNonDealerPay} / ${points.tsumoDealerPay}点',
        style: style,
      );
    }
    return const SizedBox.shrink();
  }
}
