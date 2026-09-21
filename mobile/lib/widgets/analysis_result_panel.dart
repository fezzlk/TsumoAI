import 'package:flutter/material.dart';

import 'tile_glyph.dart';

/// Displays tenpai/discard analysis with tile illustrations while keeping the
/// numeric parts of the result easy to scan.
class AnalysisResultPanel extends StatelessWidget {
  final Map<String, dynamic> result;

  const AnalysisResultPanel({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final shanten = _asInt(result['shanten']);
    final improvingTiles = _maps(result['improving_tiles']);
    final discards = _maps(result['discards']);
    final calls = _maps(result['calls']);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'シャンテン数: $shanten',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (improvingTiles.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              shanten == 0 ? '待ち牌' : '有効牌',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 6),
            _ImprovingTiles(tiles: improvingTiles, keyPrefix: 'analysis-wait'),
          ] else if (result.containsKey('improving_tiles')) ...[
            const SizedBox(height: 8),
            const Text('有効牌・待ち: なし', style: TextStyle(color: Colors.white70)),
          ],
          if (discards.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (var index = 0; index < discards.length; index++) ...[
              if (index > 0) const SizedBox(height: 8),
              _DiscardResult(item: discards[index], index: index),
            ],
          ],
          if (calls.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              '鳴ける可能性',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 6),
            for (var index = 0; index < calls.length; index++) ...[
              if (index > 0) const SizedBox(height: 8),
              _CallResult(item: calls[index], index: index),
            ],
            const SizedBox(height: 8),
            const Text(
              '役・守備・点数状況は含まない牌効率上の候補です。',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ] else if (result.containsKey('calls')) ...[
            const SizedBox(height: 8),
            const Text('現在の手牌から鳴ける候補はありません'),
          ],
        ],
      ),
    );
  }
}

class _CallResult extends StatelessWidget {
  const _CallResult({required this.item, required this.index});

  final Map<String, dynamic> item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final callTile = item['call_tile']?.toString() ?? '?';
    final type = switch (item['call_type']) {
      'chi' => 'チー',
      'pon' => 'ポン',
      'kan' => 'カン',
      _ => item['call_type']?.toString() ?? '?',
    };
    final recommendation = switch (item['recommendation']) {
      'improves' => 'シャンテン数が進む',
      'keeps' => 'シャンテン数を維持',
      _ => 'シャンテン数が戻る',
    };
    final consumed = (item['consumed_tiles'] as List<dynamic>? ?? const [])
        .map((tile) => tile.toString())
        .toList(growable: false);
    final discards = _maps(item['discards']);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(type, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              _TileImage(
                tileCode: callTile,
                semanticPrefix: '鳴く牌',
                tileKey: ValueKey('analysis-call-$callTile-$index'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  recommendation,
                  style: const TextStyle(color: Colors.lightBlueAccent),
                ),
              ),
            ],
          ),
          if (consumed.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('手牌から:', style: TextStyle(color: Colors.white70)),
                for (var i = 0; i < consumed.length; i++)
                  _TileImage(
                    tileCode: consumed[i],
                    semanticPrefix: '使用牌',
                    tileKey: ValueKey('analysis-call-$index-consumed-$i'),
                  ),
              ],
            ),
          ],
          if (discards.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '鳴いた後の候補: ${discards.map((item) => item['discard']).join('・')}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

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

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '打牌',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 6),
              _TileImage(
                tileCode: discard,
                semanticPrefix: '打牌',
                tileKey: ValueKey('analysis-discard-$discard-$index'),
              ),
              const SizedBox(width: 8),
              Text(
                '$shantenシャンテン',
                style: const TextStyle(color: Colors.white),
              ),
              const Spacer(),
              Text(
                '有効牌 $totalRemaining枚',
                style: const TextStyle(
                  color: Colors.lightBlueAccent,
                  fontSize: 12,
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
                style: const TextStyle(color: Colors.white70, fontSize: 10),
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
          fallbackTextStyle: const TextStyle(color: Colors.white, fontSize: 10),
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
