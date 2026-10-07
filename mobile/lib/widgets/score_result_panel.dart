import 'package:flutter/material.dart';

import '../models/score_result.dart';
import '../models/score_request.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Displays the same confirmed hand as both a tsumo and ron result: two
/// tinted cards side by side (tsumo green, ron blue) with the payment as the
/// largest figure.
class ScoreResultPanel extends StatelessWidget {
  const ScoreResultPanel({
    super.key,
    required this.tsumoResponse,
    required this.ronResponse,
    this.tsumoNote,
    this.ronNote,
    this.ruleSettings = const MahjongRuleSettings(),
    this.isOpenHand = false,
  });

  final ScoreResponse? tsumoResponse;
  final ScoreResponse? ronResponse;

  /// Why a side has no result (e.g. 役なし for ロン on a 門前清自摸和-only
  /// hand); defaults to a generic note.
  final String? tsumoNote;
  final String? ronNote;
  final MahjongRuleSettings ruleSettings;
  final bool isOpenHand;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ResultCard(
              label: 'ツモの場合',
              result: tsumoResponse?.result,
              note: tsumoNote,
              isTsumo: true,
              tint: colors.tsumoCard,
              panel: this,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ResultCard(
              label: 'ロンの場合',
              result: ronResponse?.result,
              note: ronNote,
              isTsumo: false,
              tint: colors.ronCard,
              panel: this,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.label,
    required this.result,
    this.note,
    required this.isTsumo,
    required this.tint,
    required this.panel,
  });

  final String label;
  final ScoreResult? result;
  final String? note;
  final bool isTsumo;
  final TintColors tint;
  final ScoreResultPanel panel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ink = tint.onContainer;
    final result = this.result;
    return Container(
      constraints: const BoxConstraints(minHeight: 190),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: tint.container,
        border: Border.all(color: tint.border),
        borderRadius: BorderRadius.circular(AppRadius.xLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.titleSmall?.copyWith(color: ink)),
          const SizedBox(height: AppSpacing.l),
          if (result == null)
            Text(
              note ?? 'この条件では和了として成立しません',
              style: text.bodySmall?.copyWith(color: ink),
            )
          else ...[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _payment(result),
                maxLines: 1,
                style: text.headlineMedium?.copyWith(color: ink),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _paymentCaption(result),
              style: text.bodySmall?.copyWith(color: ink),
            ),
            if (_isNamedLimit(result.pointLabel)) ...[
              const SizedBox(height: AppSpacing.s),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                child: Text(
                  result.pointLabel,
                  style: text.labelMedium?.copyWith(color: ink),
                ),
              ),
            ],
            const Spacer(),
            Divider(height: AppSpacing.xl, color: tint.border),
            Text(
              '${result.han}翻 ${result.fu}符',
              style: text.titleMedium?.copyWith(color: ink),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              result.yaku.map((y) => y.name).join('・'),
              style: text.bodyMedium?.copyWith(color: ink),
            ),
            if (panel.ruleSettings.chipsEnabled) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                _chips(result),
                style: text.labelMedium?.copyWith(color: ink),
              ),
            ],
            if (result.fuBreakdown.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                '符内訳: ${result.fuBreakdown.map((f) => '${f.name}${f.fu}').join(' + ')}',
                style: text.bodySmall?.copyWith(color: ink),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _payment(ScoreResult result) {
    final points = result.points;
    if (!isTsumo) return _format(points.ron);
    if (points.tsumoDealerPay == points.tsumoNonDealerPay) {
      return '${_format(points.tsumoNonDealerPay)} オール';
    }
    return '${_format(points.tsumoNonDealerPay)} / ${_format(points.tsumoDealerPay)}';
  }

  String _paymentCaption(ScoreResult result) {
    final points = result.points;
    if (!isTsumo) return '放銃者の支払い';
    if (points.tsumoDealerPay == points.tsumoNonDealerPay) return '子それぞれの支払い';
    return '子の支払い / 親の支払い';
  }

  String _chips(ScoreResult result) {
    if (panel.isOpenHand && !panel.ruleSettings.openHandChipsEnabled) {
      return 'チップ: なし（副露あり）';
    }
    final red = result.dora.akaDora;
    final ura = result.dora.uraDora;
    final ippatsu = result.yaku.any((item) => item.name == '一発') ? 1 : 0;
    final allStar = red >= 3 ? 2 : 0;
    final chips = red + ura + ippatsu + allStar;
    final equivalent = chips * 1000;
    final payment = isTsumo ? '各$chips枚・合計${chips * 3}枚' : '$chips枚';
    return 'チップ: $payment（$chipsチップ点 / 素点$equivalent点相当）';
  }

  static bool _isNamedLimit(String label) =>
      RegExp(r'満|跳|倍|役満').hasMatch(label);

  static String _format(int value) => value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
}
