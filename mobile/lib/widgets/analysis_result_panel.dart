import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'tile_glyph.dart';

/// Displays tenpai/discard analysis with tile illustrations while keeping the
/// numeric parts of the result easy to scan.
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('シャンテン数: $shanten', style: text.titleMedium),
            if (improvingTiles.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(shanten == 0 ? '待ち牌' : '有効牌', style: text.titleSmall),
              const SizedBox(height: 6),
              _ImprovingTiles(
                tiles: improvingTiles,
                keyPrefix: 'analysis-wait',
              ),
            ] else if (result.containsKey('improving_tiles')) ...[
              const SizedBox(height: 8),
              Text('有効牌・待ち: なし', style: text.bodyMedium),
            ],
            if (discards.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('牌効率重視の上位3候補', style: text.titleSmall),
              const SizedBox(height: 2),
              Text('他家の立直・捨て牌・点数状況は考慮していません。', style: text.bodySmall),
              const SizedBox(height: 8),
              for (var index = 0; index < discards.length; index++) ...[
                if (index > 0) const SizedBox(height: 8),
                _DiscardResult(item: discards[index], index: index),
              ],
              if (onAskAiWithDiscardFocus != null) ...[
                const SizedBox(height: 12),
                Text('別の判断基準でAIに相談', style: text.titleSmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final focus in ['打点優先', '即和了優先', '守備考慮'])
                      ActionChip(
                        label: Text(focus),
                        onPressed: () => onAskAiWithDiscardFocus!(focus),
                      ),
                  ],
                ),
              ],
            ],
            if (calls.isNotEmpty) ...[
              const SizedBox(height: 10),
              _CallResults(
                calls: calls,
                currentShanten: shanten,
                onAskAi: onAskAiAboutCall,
              ),
              const SizedBox(height: 8),
              Text(
                'チーは上家から出た場合だけ可能です。役・守備・点数状況は含まない牌効率上の候補です。',
                style: text.bodySmall,
              ),
            ] else if (result.containsKey('calls')) ...[
              const SizedBox(height: 8),
              const Text('現在の手牌から鳴ける候補はありません'),
            ],
          ],
        ),
      ),
    );
  }
}

enum _CallRecommendation { recommended, conditional, skip }

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
    final grouped =
        <_CallRecommendation, List<({Map<String, dynamic> item, int index})>>{
          for (final value in _CallRecommendation.values) value: [],
        };
    for (var index = 0; index < calls.length; index++) {
      grouped[_recommendationOf(calls[index])]!.add((
        item: calls[index],
        index: index,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final recommendation in _CallRecommendation.values)
          if (grouped[recommendation]!.isNotEmpty) ...[
            if (recommendation != _CallRecommendation.recommended)
              const SizedBox(height: 10),
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
  final List<({Map<String, dynamic> item, int index})> entries;
  final int currentShanten;
  final ValueChanged<Map<String, dynamic>>? onAskAi;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    final (label, icon, color, container) = switch (recommendation) {
      _CallRecommendation.recommended => (
        '推奨',
        Icons.thumb_up_alt_outlined,
        colors.success.color,
        colors.success.container,
      ),
      _CallRecommendation.conditional => (
        '条件付き',
        Icons.help_outline,
        colors.warning.color,
        colors.warning.container,
      ),
      _CallRecommendation.skip => (
        '見送り',
        Icons.do_not_disturb_alt,
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: container,
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in entries)
                _CallCandidateButton(
                  item: entry.item,
                  index: entry.index,
                  currentShanten: currentShanten,
                  accent: color,
                  onAskAi: onAskAi,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CallCandidateButton extends StatelessWidget {
  const _CallCandidateButton({
    required this.item,
    required this.index,
    required this.currentShanten,
    required this.accent,
    this.onAskAi,
  });

  final Map<String, dynamic> item;
  final int index;
  final int currentShanten;
  final Color accent;
  final ValueChanged<Map<String, dynamic>>? onAskAi;

  @override
  Widget build(BuildContext context) {
    final callTile = item['call_tile']?.toString() ?? '?';
    final type = _callTypeLabel(item['call_type']);
    final after = _asInt(item['shanten_after_call']);
    return Semantics(
      button: true,
      label: '$callTileを$typeする候補の詳細',
      child: InkWell(
        key: ValueKey('analysis-call-candidate-$index'),
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _CallDetailDialog(
            item: item,
            index: index,
            currentShanten: currentShanten,
            onAskAi: onAskAi,
          ),
        ),
        child: Container(
          constraints: const BoxConstraints(minWidth: 92, minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TileImage(
                tileCode: callTile,
                semanticPrefix: '鳴く牌',
                tileKey: ValueKey('analysis-call-$callTile-$index'),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '$currentShanten → $after向聴',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: accent),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallDetailDialog extends StatelessWidget {
  const _CallDetailDialog({
    required this.item,
    required this.index,
    required this.currentShanten,
    this.onAskAi,
  });

  final Map<String, dynamic> item;
  final int index;
  final int currentShanten;
  final ValueChanged<Map<String, dynamic>>? onAskAi;

  @override
  Widget build(BuildContext context) {
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
    final reason = switch (recommendation) {
      _CallRecommendation.recommended => '向聴数が進むため、牌効率では有力な候補です。',
      _CallRecommendation.conditional => '向聴数は変わりません。受け入れ、成立する役、打点を確認して選びます。',
      _CallRecommendation.skip => '向聴数が戻るため、通常は見送ります。役や打点など明確な目的がある場合は再検討できます。',
    };

    return AlertDialog(
      title: Text('$typeの詳細'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              if (possibleYaku.isNotEmpty) ...[
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
              onAskAi!(item);
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

_CallRecommendation _recommendationOf(Map<String, dynamic> item) =>
    switch (item['recommendation']) {
      'improves' => _CallRecommendation.recommended,
      'keeps' => _CallRecommendation.conditional,
      _ => _CallRecommendation.skip,
    };

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
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${index + 1}位', style: text.titleSmall),
              _TileImage(
                tileCode: discard,
                semanticPrefix: '打牌',
                tileKey: ValueKey('analysis-discard-$discard-$index'),
              ),
              Text('$shantenシャンテン', style: text.bodyMedium),
              Text(
                '有効牌 $totalRemaining枚',
                style: text.bodyMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
      spacing: 8,
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

  const _TileImage({
    required this.tileCode,
    required this.semanticPrefix,
    required this.tileKey,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$semanticPrefix $tileCode',
      image: true,
      child: SizedBox(
        key: tileKey,
        width: 30,
        height: 42,
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
