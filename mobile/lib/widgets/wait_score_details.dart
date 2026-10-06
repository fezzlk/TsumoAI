import 'package:flutter/material.dart';

/// Scores for this particular winning tile, with independent ron/tsumo yaku.
class WaitScoreDetails extends StatelessWidget {
  const WaitScoreDetails({super.key, required this.tile});

  final Map<String, dynamic> tile;

  @override
  Widget build(BuildContext context) {
    if (tile.containsKey('ron_score') || tile.containsKey('tsumo_score')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WinScore(
            label: 'ロン',
            score: _map(tile['ron_score']),
            error: tile['ron_score_error'],
          ),
          const SizedBox(height: 10),
          _WinScore(
            label: 'ツモ',
            score: _map(tile['tsumo_score']),
            error: tile['tsumo_score_error'],
          ),
        ],
      );
    }
    // Older saved results only contain the score for one win type.
    final score = _map(tile['score']);
    final points = _map(score['points']);
    final label = _number(points['ron']) > 0
        ? 'ロン'
        : _number(points['tsumo_dealer_pay']) > 0
        ? 'ツモ'
        : '保存時の条件';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WinScore(label: label, score: score, error: tile['score_error']),
        Text(
          '再解析するとロン・ツモ両方を確認できます。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _WinScore extends StatelessWidget {
  const _WinScore({required this.label, required this.score, this.error});

  final String label;
  final Map<String, dynamic> score;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (score.isEmpty) {
      final noYaku = error == 'No yaku: dora-only hands cannot win';
      return Text(
        noYaku
            ? '$label: 役なし（この条件では和了できません）'
            : error != null
            ? '$label: 役・打点を判定できませんでした'
            : '$label: 役・打点は未算定',
        style: text.bodyMedium?.copyWith(
          color: noYaku ? Theme.of(context).colorScheme.error : null,
        ),
      );
    }
    final points = _map(score['points']);
    final payments = _map(score['payments']);
    final dealerPay = _number(points['tsumo_dealer_pay']);
    final nonDealerPay = _number(points['tsumo_non_dealer_pay']);
    final handPoints = _number(
      payments['hand_points_received'] ??
          (label == 'ロン' ? points['ron'] : dealerPay + nonDealerPay * 2),
    );
    final yakuman = (score['yakuman'] as List<dynamic>? ?? const [])
        .map((name) => name.toString())
        .toList();
    final yaku = (score['yaku'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => !const {'ドラ', '赤ドラ', '裏ドラ'}.contains(item['name']));
    final dora = _map(score['dora']);
    final bonuses = [
      for (final (key, name) in [
        ('dora', 'ドラ'),
        ('aka_dora', '赤ドラ'),
        ('ura_dora', '裏ドラ'),
      ])
        if (_number(dora[key]) > 0) '$name${_number(dora[key])}',
    ];
    final honba = _number(payments['honba_bonus']);
    final kyotaku = _number(payments['kyotaku_bonus']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          handPoints > 0
              ? '$label $handPoints点${label == 'ツモ' ? '（合計）' : ''}'
              : '$label: 打点は未算定',
          style: text.titleSmall,
        ),
        if (label == 'ツモ' && dealerPay > 0)
          Text(
            dealerPay == nonDealerPay
                ? '$dealerPay点オール'
                : '子 $nonDealerPay点・親 $dealerPay点払い',
            style: text.bodySmall,
          ),
        Text(
          yakuman.isNotEmpty
              ? score['point_label']?.toString() ?? '役満'
              : '${score['han']}翻 ${score['fu']}符'
                    '${score['point_label'] != null && score['point_label'] != '通常' ? '・${score['point_label']}' : ''}',
          style: text.bodySmall,
        ),
        Text(
          '役: ${yakuman.isNotEmpty ? yakuman.join('・') : yaku.map((item) => '${item['name']} ${item['han']}翻').join('・')}',
          style: text.bodyMedium,
        ),
        if (bonuses.isNotEmpty) Text(bonuses.join('・'), style: text.bodySmall),
        if (honba > 0 || kyotaku > 0)
          Text(
            [
              if (honba > 0) '本場 +$honba点',
              if (kyotaku > 0) '供託 +$kyotaku点',
              '受取合計 ${_number(payments['total_received'])}点',
            ].join('・'),
            style: text.bodySmall,
          ),
      ],
    );
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
int _number(Object? value) => value is num ? value.toInt() : 0;
