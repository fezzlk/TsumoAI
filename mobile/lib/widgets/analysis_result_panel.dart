import 'package:flutter/material.dart';

import '../services/tile_assets.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'status_banner.dart';
import 'tile_glyph.dart';
import 'wait_score_details.dart';

/// Displays wait / discard / call analysis as in the result mockups: large
/// tile illustrations with the numbers that matter next to them.
class AnalysisResultPanel extends StatelessWidget {
  final Map<String, dynamic> result;
  final ValueChanged<Map<String, dynamic>>? onAskAiAboutCall;
  final ValueChanged<String>? onAskAiWithDiscardFocus;

  const AnalysisResultPanel({
    super.key,
    required this.result,
    this.onAskAiAboutCall,
    this.onAskAiWithDiscardFocus,
  });

  @override
  Widget build(BuildContext context) {
    final shanten = _asInt(result['shanten'] ?? result['current_shanten']);
    final improvingTiles = _maps(result['improving_tiles']);
    final discards = _maps(result['discards']).take(3).toList(growable: false);
    final calls = _maps(result['calls']);
    final text = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.containsKey('improving_tiles') && discards.isEmpty)
          _WaitResult(
            shanten: shanten,
            tiles: improvingTiles,
            scoreConditions:
                (result['score_conditions'] as List<dynamic>? ?? const [])
                    .map((value) => value.toString())
                    .toList(),
          ),
        if (discards.isNotEmpty) ...[
          if (onAskAiWithDiscardFocus != null) ...[
            _FocusChips(onAsk: onAskAiWithDiscardFocus!),
            const SizedBox(height: AppSpacing.l),
          ],
          if (_tenpaiNotice(result) case final notice?) ...[
            StatusBanner(kind: StatusKind.success, message: notice),
            const SizedBox(height: AppSpacing.m),
          ],
          _SectionTitle(
            eyebrow: shanten == 0 ? 'テンパイ' : '$shantenシャンテン',
            title: '打牌候補 ベスト3',
            trailing: '牌効率を優先した結果',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('他家の立直・捨て牌・点数状況は考慮していません。', style: text.bodySmall),
          const SizedBox(height: AppSpacing.s),
          for (var index = 0; index < discards.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.s),
            _DiscardResult(item: discards[index], index: index),
          ],
        ],
        if (calls.isNotEmpty) ...[
          _CallResults(
            calls: calls,
            currentShanten: shanten,
            onAskAi: onAskAiAboutCall,
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'チーは上家から出た場合だけ可能です。役と打点は表示した条件での見通しです。フリテン・喰い替え・他家の捨て牌・守備は判定していません。',
            style: text.bodySmall,
          ),
        ] else if (result.containsKey('calls')) ...[
          const SizedBox(height: AppSpacing.s),
          Text('現在の手牌から鳴ける候補はありません', style: text.bodyMedium),
        ],
      ],
    );
  }
}

/// 何を切る: says when the 14-tile hand is already complete or tenpai. The
/// candidates stay listed below, since a tenpai hand may still swap tiles
/// for a better hand or more points.
String? _tenpaiNotice(Map<String, dynamic> result) {
  if (_asInt(result['shanten']) != 0) return null;
  if (result['hand_shanten'] == -1) {
    return '和了形です（このままツモ和了できます）。打点を上げる打牌も候補に出しています。';
  }
  final keeping = <String>[
    for (final item in _maps(result['discards']))
      if (_asInt(item['shanten']) == 0) tileDisplayName(item['discard'].toString()),
  ];
  final unique = keeping.toSet().join('・');
  return 'すでに聴牌しています（$uniqueを切ると聴牌）。手役や打点を上げる打牌も候補に出しています。';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.eyebrow,
    required this.title,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                style: text.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Text(title, style: text.headlineSmall),
            ],
          ),
        ),
        if (trailing != null) Text(trailing!, style: text.bodySmall),
      ],
    );
  }
}

/// Discard focus row: 牌効率 is the computed result; the others ask AI.
class _FocusChips extends StatelessWidget {
  const _FocusChips({required this.onAsk});

  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget chip(String label, {required bool selected, VoidCallback? onTap}) =>
        Material(
          color: selected ? scheme.primary : scheme.surface,
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSizes.chip),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    label,
                    style: text.labelMedium?.copyWith(
                      color: selected ? scheme.onPrimary : scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            chip('牌効率', selected: true),
            for (final focus in ['打点優先', '即和了優先', '守備考慮'])
              chip(focus, selected: false, onTap: () => onAsk(focus)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text('別の判断基準でAIに相談', style: text.bodySmall),
      ],
    );
  }
}

class _WaitResult extends StatelessWidget {
  const _WaitResult({
    required this.shanten,
    required this.tiles,
    required this.scoreConditions,
  });

  final int shanten;
  final List<Map<String, dynamic>> tiles;
  final List<String> scoreConditions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = context.appColors;
    final tenpai = shanten == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: colors.soft,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Text(
              tenpai ? 'テンパイ' : '$shantenシャンテン',
              style: text.labelMedium?.copyWith(color: colors.success.color),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Text(
          tiles.isEmpty
              ? (tenpai ? '待ち牌はありません' : '有効牌はありません')
              : tenpai
              ? '待ち牌は${tiles.length}種類'
              : '有効牌は${tiles.length}種類',
          textAlign: TextAlign.center,
          style: text.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          tenpai ? '和了形になる牌です。役の有無はロン・ツモ別に確認してください。' : '引くと向聴数が進む牌です',
          textAlign: TextAlign.center,
          style: text.bodySmall,
        ),
        if (tenpai) ...[
          const SizedBox(height: AppSpacing.xs),
          if (scoreConditions.isNotEmpty)
            Text(scoreConditions.join('・'), style: text.bodySmall),
          Text('現在の入力条件・ドラで計算。本場・供託は別記。フリテンは未判定です。', style: text.bodySmall),
        ],
        const SizedBox(height: AppSpacing.l),
        if (tenpai)
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _WaitCard(tile: tiles[i], index: i, showScores: true),
          ],
        if (!tenpai)
          for (var i = 0; i < tiles.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _WaitCard(tile: tiles[i], index: i),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: i + 1 < tiles.length
                        ? _WaitCard(tile: tiles[i + 1], index: i + 1)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
      ],
    );
  }
}

class _WaitCard extends StatelessWidget {
  const _WaitCard({
    required this.tile,
    required this.index,
    this.showScores = false,
  });

  final Map<String, dynamic> tile;
  final int index;
  final bool showScores;

  @override
  Widget build(BuildContext context) {
    final tint = context.appColors.tsumoCard;
    final text = Theme.of(context).textTheme;
    final code = tile['tile']?.toString() ?? '?';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: tint.container,
        border: Border.all(color: tint.border),
        borderRadius: BorderRadius.circular(AppRadius.xLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TileImage(
                tileCode: code,
                semanticPrefix: '待ち牌',
                tileKey: ValueKey('analysis-wait-$code-$index'),
                width: 40,
                height: 54,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tileDisplayName(code),
                      style: text.titleSmall?.copyWith(color: tint.onContainer),
                    ),
                    Text(
                      '残り${_asInt(tile['remaining'])}枚',
                      style: text.bodySmall?.copyWith(color: tint.onContainer),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showScores) ...[
            const SizedBox(height: 10),
            WaitScoreDetails(tile: tile),
          ],
        ],
      ),
    );
  }
}

enum _CallRecommendation { recommended, conditional, skip }

class _CallCandidateGroup {
  _CallCandidateGroup(this.index);

  final int index;
  final List<Map<String, dynamic>> variants = [];
  final Set<String> shapes = {};
  Map<String, dynamic> get item => variants.first;

  void add(Map<String, dynamic> candidate) {
    final consumed =
        (candidate['consumed_tiles'] as List<dynamic>? ?? const [])
            .map((tile) => tile.toString())
            .toList()
          ..sort();
    if (!shapes.add(consumed.join(','))) return;
    // The list shows one concrete shape, never a blend of different shapes'
    // yaku or points. Prefer the safer recommendation, then tile efficiency.
    if (variants.isNotEmpty) {
      final comparison = _recommendationOf(
        candidate,
      ).index.compareTo(_recommendationOf(item).index);
      if (comparison < 0 ||
          (comparison == 0 &&
              _asInt(candidate['shanten_after_call']) <
                  _asInt(item['shanten_after_call']))) {
        variants.insert(0, candidate);
        return;
      }
    }
    variants.add(candidate);
  }
}

class _CallResults extends StatelessWidget {
  const _CallResults({
    required this.calls,
    required this.currentShanten,
    this.onAskAi,
  });

  final List<Map<String, dynamic>> calls;
  final int currentShanten;
  final ValueChanged<Map<String, dynamic>>? onAskAi;

  @override
  Widget build(BuildContext context) {
    final candidates = <String, _CallCandidateGroup>{};
    for (var index = 0; index < calls.length; index++) {
      final item = calls[index];
      final key = '${item['call_type']}:${item['call_tile']}';
      (candidates[key] ??= _CallCandidateGroup(index)).add(item);
    }
    final grouped = <_CallRecommendation, List<_CallCandidateGroup>>{
      for (final value in _CallRecommendation.values) value: [],
    };
    for (final candidate in candidates.values) {
      grouped[_recommendationOf(candidate.item)]!.add(candidate);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final recommendation in _CallRecommendation.values)
          if (grouped[recommendation]!.isNotEmpty) ...[
            if (recommendation != _CallRecommendation.recommended)
              const SizedBox(height: 9),
            _CallRecommendationGroup(
              recommendation: recommendation,
              entries: grouped[recommendation]!,
              currentShanten: currentShanten,
              onAskAi: onAskAi,
            ),
          ],
      ],
    );
  }
}

class _CallRecommendationGroup extends StatelessWidget {
  const _CallRecommendationGroup({
    required this.recommendation,
    required this.entries,
    required this.currentShanten,
    this.onAskAi,
  });

  final _CallRecommendation recommendation;
  final List<_CallCandidateGroup> entries;
  final int currentShanten;
  final ValueChanged<Map<String, dynamic>>? onAskAi;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final (label, caption, container, border) = switch (recommendation) {
      _CallRecommendation.recommended => (
        '推奨',
        '手を進めやすい',
        colors.recommended.container,
        colors.recommended.border,
      ),
      _CallRecommendation.conditional => (
        '条件付き',
        '方針により選択',
        colors.conditional.container,
        colors.conditional.border,
      ),
      _CallRecommendation.skip => (
        '見送り',
        '現状では非推奨',
        scheme.surface,
        scheme.outlineVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: container,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: text.titleSmall)),
              Text(caption, style: text.bodySmall),
            ],
          ),
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) Divider(height: AppSpacing.l, color: border),
            _CallCandidateRow(
              item: entries[i].item,
              variants: entries[i].variants,
              index: entries[i].index,
              currentShanten: currentShanten,
              recommendation: recommendation,
              onAskAi: onAskAi,
            ),
          ],
        ],
      ),
    );
  }
}

class _CallCandidateRow extends StatelessWidget {
  const _CallCandidateRow({
    required this.item,
    required this.variants,
    required this.index,
    required this.currentShanten,
    required this.recommendation,
    this.onAskAi,
  });

  final Map<String, dynamic> item;
  final List<Map<String, dynamic>> variants;
  final int index;
  final int currentShanten;
  final _CallRecommendation recommendation;
  final ValueChanged<Map<String, dynamic>>? onAskAi;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final callTile = item['call_tile']?.toString() ?? '?';
    final type = _callTypeLabel(item['call_type']);
    final after = _asInt(item['shanten_after_call']);
    final yaku = (item['possible_yaku'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    return Semantics(
      button: true,
      label: '$callTileを$typeする候補の詳細',
      child: InkWell(
        key: ValueKey('analysis-call-candidate-$index'),
        borderRadius: BorderRadius.circular(AppRadius.large),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _CallDetailDialog(
            variants: variants,
            index: index,
            currentShanten: currentShanten,
            onAskAi: onAskAi,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  _TileImage(
                    tileCode: callTile,
                    semanticPrefix: '鳴く牌',
                    tileKey: ValueKey('analysis-call-$callTile-$index'),
                    width: 46,
                    height: 62,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _CallTypeBadge(callType: item['call_type']),
                ],
              ),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item['outlook'] is Map) ...[
                      _CallOutlookView(outlook: _outlookMap(item['outlook'])),
                      const SizedBox(height: AppSpacing.s),
                    ],
                    if (variants.length > 1) ...[
                      Text(
                        '使う手牌は${variants.length}通り（詳細で比較）',
                        style: text.labelLarge,
                      ),
                      Text('表示は次の手牌を使う場合の評価です。', style: text.bodySmall),
                      Wrap(
                        spacing: 4,
                        children: [
                          for (final (tileIndex, tile)
                              in (item['consumed_tiles'] as List<dynamic>)
                                  .indexed)
                            _TileImage(
                              tileCode: tile.toString(),
                              semanticPrefix: '表示中の使用牌',
                              tileKey: ValueKey(
                                'analysis-call-$index-summary-consumed-$tileIndex',
                              ),
                              width: 26,
                              height: 36,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    Text(
                      '$currentShanten → $afterシャンテン',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      [
                        _callReason(item, recommendation),
                        if (item['outlook'] is! Map && yaku.isNotEmpty)
                          '狙える役: ${yaku.join('・')}',
                      ].join(' '),
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item['call_type'] == 'chi'
                          ? '上家から切られた場合のみ成立'
                          : 'どの相手からでも成立',
                      style: text.labelMedium?.copyWith(color: scheme.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _callReason(
  Map<String, dynamic> item,
  _CallRecommendation recommendation,
) {
  final status = _outlookMap(item['outlook'])['status'];
  if (status == 'no_yaku') return '向聴数が進んでも、今の待ちでは役がありません。';
  if (status == 'conditional') return '狙う役の条件を満たせるか確認してから鳴きます。';
  if (status == 'unknown') return '役を確認できていないため、牌効率だけで鳴く判断はできません。';
  return switch (recommendation) {
    _CallRecommendation.recommended => '向聴数が進むため、牌効率では有力な候補です。',
    _CallRecommendation.conditional => '向聴数は変わりません。受け入れ・役・打点で判断します。',
    _CallRecommendation.skip => '向聴数が戻るため、通常は見送ります。',
  };
}

Map<String, dynamic> _outlookMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

String _callWaitPayment(Map<String, dynamic> wait) {
  if (wait['win_type'] == 'tsumo') {
    final dealer = wait['tsumo_dealer_pay'];
    final nonDealer = wait['tsumo_non_dealer_pay'];
    if (dealer == null || nonDealer == null) return '';
    return dealer == nonDealer
        ? ' / $dealer点オール'
        : ' / 子$nonDealer・親$dealer点払い';
  }
  return wait['ron_points'] == null ? '' : ' / ${wait['ron_points']}点';
}

class _CallOutlookView extends StatelessWidget {
  const _CallOutlookView({required this.outlook, this.detailed = false});

  final Map<String, dynamic> outlook;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final yaku = _maps(outlook['yaku']);
    final estimate = _outlookMap(outlook['score_estimate']);
    final warnings = (outlook['warnings'] as List<dynamic>? ?? const []).map(
      (value) => value.toString(),
    );
    final winning = _maps(outlook['winning_tiles']);
    final noYaku = (outlook['no_yaku_tiles'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList();
    final isReference = outlook['status'] == 'conditional';
    final minimum = _asInt(estimate['min_points']);
    final maximum = _asInt(estimate['max_points']);
    final paymentLabel = estimate['win_type'] == 'tsumo' ? 'ツモ合計' : 'ロン';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          outlook['summary']?.toString() ?? '役・打点は未確認です',
          style: text.titleSmall?.copyWith(
            color: outlook['status'] == 'no_yaku'
                ? Theme.of(context).colorScheme.error
                : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          estimate.isEmpty
              ? '打点: 未算定'
              : '${isReference ? '条件成立時の参考打点' : '打点の目安'}: '
                    '${minimum == maximum ? '$minimum' : '$minimum〜$maximum'}点（$paymentLabel）',
          style: text.bodyMedium,
        ),
        if (detailed && estimate.isNotEmpty)
          Text(estimate['basis']?.toString() ?? '', style: text.bodySmall),
        if (!detailed && isReference && estimate.isNotEmpty)
          Text('各役が単独で成立・30〜40符・ドラなしの参考値', style: text.bodySmall),
        if (yaku.isNotEmpty) ...[
          const SizedBox(height: 6),
          if (detailed) ...[
            Text('役と成立条件', style: text.titleSmall),
            for (final item in yaku)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${item['name']}（${item['han']}翻）: ${item['condition']}',
                ),
              ),
          ] else
            Text(
              '狙える役: ${yaku.map((item) => '${item['name']} ${item['han']}翻').toSet().join('・')}',
            ),
        ],
        for (final warning in detailed ? warnings : warnings.take(2)) ...[
          const SizedBox(height: 4),
          Text(warning, style: text.bodySmall),
        ],
        if (detailed && winning.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('役が付く待ち', style: text.titleSmall),
          for (final wait in winning)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  _TileImage(
                    tileCode: wait['tile'].toString(),
                    semanticPrefix: '役ありの待ち',
                    tileKey: ValueKey('call-winning-${wait['tile']}'),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${wait['win_type'] == 'tsumo' ? 'ツモ' : 'ロン'}: '
                      '${(wait['yaku'] as List<dynamic>? ?? const []).join('・')} '
                      '${wait['han']}翻${wait['fu']}符'
                      '${_callWaitPayment(wait)}',
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (detailed && noYaku.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('この待ちは役なし', style: text.titleSmall),
          Wrap(
            spacing: 4,
            children: [
              for (final tile in noYaku)
                _TileImage(
                  tileCode: tile,
                  semanticPrefix: '役なしの待ち',
                  tileKey: ValueKey('call-no-yaku-$tile'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CallDetailDialog extends StatefulWidget {
  const _CallDetailDialog({
    required this.variants,
    required this.index,
    required this.currentShanten,
    this.onAskAi,
  });

  final List<Map<String, dynamic>> variants;
  final int index;
  final int currentShanten;
  final ValueChanged<Map<String, dynamic>>? onAskAi;

  @override
  State<_CallDetailDialog> createState() => _CallDetailDialogState();
}

class _CallDetailDialogState extends State<_CallDetailDialog> {
  int _selectedVariant = 0;

  @override
  Widget build(BuildContext context) {
    final item = widget.variants[_selectedVariant];
    final index = widget.index;
    final currentShanten = widget.currentShanten;
    final onAskAi = widget.onAskAi;
    final callTile = item['call_tile']?.toString() ?? '?';
    final type = _callTypeLabel(item['call_type']);
    final consumed = (item['consumed_tiles'] as List<dynamic>? ?? const [])
        .map((tile) => tile.toString())
        .toList(growable: false);
    final discards = _maps(item['discards']);
    final replacementTiles = _maps(item['replacement_tiles']);
    final possibleYaku = (item['possible_yaku'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    final recommendation = _recommendationOf(item);
    final after = _asInt(item['shanten_after_call']);
    final reason = _callReason(item, recommendation);

    return AlertDialog(
      title: Text('$typeの詳細'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.variants.length > 1) ...[
                Text(
                  '使う手牌を選択（${widget.variants.length}通り）',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (
                      var variantIndex = 0;
                      variantIndex < widget.variants.length;
                      variantIndex++
                    )
                      ChoiceChip(
                        key: ValueKey('analysis-call-variant-$variantIndex'),
                        selected: _selectedVariant == variantIndex,
                        onSelected: (_) =>
                            setState(() => _selectedVariant = variantIndex),
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (tileIndex, tile)
                                in (widget.variants[variantIndex]['consumed_tiles']
                                        as List<dynamic>)
                                    .indexed)
                              _TileImage(
                                tileCode: tile.toString(),
                                semanticPrefix: '選択する使用牌',
                                tileKey: ValueKey(
                                  'analysis-call-$index-variant-$variantIndex-tile-$tileIndex',
                                ),
                                width: 26,
                                height: 36,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (item['outlook'] is Map) ...[
                _CallOutlookView(
                  outlook: _outlookMap(item['outlook']),
                  detailed: true,
                ),
                const SizedBox(height: 14),
              ] else ...[
                const Text('役・打点の詳しい判定はありません。再解析すると確認できます。'),
                const SizedBox(height: 14),
              ],
              Text('鳴く形', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < consumed.length; i++)
                    _TileImage(
                      tileCode: consumed[i],
                      semanticPrefix: '使用牌',
                      tileKey: ValueKey('analysis-call-$index-consumed-$i'),
                    ),
                  const Text('＋'),
                  _TileImage(
                    tileCode: callTile,
                    semanticPrefix: '鳴く牌',
                    tileKey: ValueKey('analysis-call-$index-called'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('向聴数: $currentShanten → $after'),
              const SizedBox(height: 6),
              Text(reason),
              if (item['outlook'] is! Map && possibleYaku.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('成立可能役', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(possibleYaku.join('・')),
              ],
              if (item['call_type'] == 'chi') ...[
                const SizedBox(height: 6),
                const Text('上家から出た場合だけチーできます。'),
              ],
              if (discards.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  '鳴いた後に切る候補',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                for (
                  var discardIndex = 0;
                  discardIndex < discards.length;
                  discardIndex++
                ) ...[
                  _CallDiscardDetail(
                    item: discards[discardIndex],
                    callIndex: index,
                    discardIndex: discardIndex,
                  ),
                  if (discardIndex < discards.length - 1)
                    const SizedBox(height: 10),
                ],
              ],
              if (replacementTiles.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'カン後の補充牌で進む牌',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _ImprovingTiles(
                  tiles: replacementTiles,
                  keyPrefix: 'analysis-call-$index-replacement',
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (onAskAi != null)
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              onAskAi(item);
            },
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('この候補をAIに質問'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

class _CallDiscardDetail extends StatelessWidget {
  const _CallDiscardDetail({
    required this.item,
    required this.callIndex,
    required this.discardIndex,
  });

  final Map<String, dynamic> item;
  final int callIndex;
  final int discardIndex;

  @override
  Widget build(BuildContext context) {
    final discard = item['discard']?.toString() ?? '?';
    final improving = _maps(item['improving_tiles']);
    final total = _asInt(item['total_remaining']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('切る'),
            _TileImage(
              tileCode: discard,
              semanticPrefix: '打牌',
              tileKey: ValueKey(
                'analysis-call-$callIndex-discard-$discardIndex',
              ),
            ),
            if (total > 0) Text('受け入れ $total枚'),
          ],
        ),
        if (item['call_outlook'] is Map) ...[
          const SizedBox(height: 6),
          _CallOutlookView(
            outlook: _outlookMap(item['call_outlook']),
            detailed: true,
          ),
        ],
        if (improving.isNotEmpty) ...[
          const SizedBox(height: 6),
          _ImprovingTiles(
            tiles: improving,
            keyPrefix:
                'analysis-call-$callIndex-discard-$discardIndex-improving',
          ),
        ],
      ],
    );
  }
}

_CallRecommendation _recommendationOf(Map<String, dynamic> item) {
  final status = _outlookMap(item['outlook'])['status'];
  if (status == 'no_yaku' || item['recommendation'] == 'worsens') {
    return _CallRecommendation.skip;
  }
  if (status == 'conditional' || status == 'unknown') {
    return _CallRecommendation.conditional;
  }
  return switch (item['recommendation']) {
    'improves' => _CallRecommendation.recommended,
    'keeps' => _CallRecommendation.conditional,
    _ => _CallRecommendation.skip,
  };
}

/// チー・ポン・カン as a solid colored pill (blue / amber / purple) so the
/// call kind reads at a glance; the label still names it for color-blind
/// users.
class _CallTypeBadge extends StatelessWidget {
  const _CallTypeBadge({required this.callType});

  final Object? callType;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final background = switch (callType) {
      'chi' => colors.wait.accent,
      'pon' => colors.discard.accent,
      'kan' => colors.call.accent,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return Container(
      constraints: const BoxConstraints(minWidth: 46),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        _callTypeLabel(callType),
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: colors.onDark),
      ),
    );
  }
}

String _callTypeLabel(Object? value) => switch (value) {
  'chi' => 'チー',
  'pon' => 'ポン',
  'kan' => 'カン',
  _ => value?.toString() ?? '?',
};

class _DiscardResult extends StatelessWidget {
  final Map<String, dynamic> item;
  final int index;

  const _DiscardResult({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    final discard = item['discard']?.toString() ?? '?';
    final shanten = _asInt(item['shanten']);
    final improvingTiles = _maps(item['improving_tiles']);
    final totalRemaining = item['total_remaining'] is num
        ? (item['total_remaining'] as num).toInt()
        : improvingTiles.fold<int>(
            0,
            (total, tile) => total + _asInt(tile['remaining']),
          );
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final best = index == 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: best ? colors.recommended.container : scheme.surface,
        border: Border.all(
          color: best ? colors.recommended.border : scheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xLarge),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 17),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: best ? scheme.primary : scheme.onSurfaceVariant,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              semanticsLabel: '${index + 1}位',
              style: text.labelSmall?.copyWith(color: scheme.onPrimary),
            ),
          ),
          const SizedBox(width: 10),
          _TileImage(
            tileCode: discard,
            semanticPrefix: '打牌',
            tileKey: ValueKey('analysis-discard-$discard-$index'),
            width: 43,
            height: 58,
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.s,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '有効牌 $totalRemaining枚',
                      style: text.labelLarge?.copyWith(color: scheme.primary),
                    ),
                    Text('$shantenシャンテン', style: text.bodySmall),
                  ],
                ),
                if (improvingTiles.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _ImprovingTiles(
                    tiles: improvingTiles,
                    keyPrefix: 'analysis-discard-$index-wait',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImprovingTiles extends StatelessWidget {
  final List<Map<String, dynamic>> tiles;
  final String keyPrefix;

  const _ImprovingTiles({required this.tiles, required this.keyPrefix});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var index = 0; index < tiles.length; index++)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TileImage(
                tileCode: tiles[index]['tile']?.toString() ?? '?',
                semanticPrefix: '有効牌',
                tileKey: ValueKey('$keyPrefix-${tiles[index]['tile']}-$index'),
              ),
              const SizedBox(height: 2),
              Text(
                '残り${_asInt(tiles[index]['remaining'])}枚',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _TileImage extends StatelessWidget {
  final String tileCode;
  final String semanticPrefix;
  final Key tileKey;
  final double width;
  final double height;

  const _TileImage({
    required this.tileCode,
    required this.semanticPrefix,
    required this.tileKey,
    this.width = 26,
    this.height = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$semanticPrefix $tileCode',
      image: true,
      child: SizedBox(
        key: tileKey,
        width: width,
        height: height,
        child: TileGlyph(
          tileCode: tileCode,
          fallbackTextStyle: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> _maps(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

int _asInt(Object? value) => value is num ? value.toInt() : 0;
