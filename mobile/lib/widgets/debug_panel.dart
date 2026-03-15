import 'package:flutter/material.dart';
import '../services/tile_detector.dart';

class DebugPanel extends StatelessWidget {
  final TileDetectorParams params;
  final TileDetectorResult? lastResult;
  final TileDetectorResult? hResult;
  final TileDetectorResult? vResult;
  final ValueChanged<TileDetectorParams> onParamsChanged;

  const DebugPanel({
    super.key,
    required this.params,
    required this.lastResult,
    this.hResult,
    this.vResult,
    required this.onParamsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Row(
              children: [
                Icon(Icons.bug_report, color: Colors.amberAccent, size: 18),
                SizedBox(width: 6),
                Text(
                  'デバッグモード',
                  style: TextStyle(
                    color: Colors.amberAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Detection result summary
            if (lastResult != null) _buildResultSummary(lastResult!),
            if (hResult != null || vResult != null) ...[
              const SizedBox(height: 4),
              _buildAxisComparison(),
            ],
            const SizedBox(height: 8),

            // Sliders
            _buildSlider(
              label: '輝度しきい値 (Y)',
              value: params.luminanceMin.toDouble(),
              min: 80,
              max: 240,
              divisions: 32,
              onChanged: (v) => onParamsChanged(
                params.copyWith(luminanceMin: v.toInt()),
              ),
            ),
            _buildSlider(
              label: '色差許容 (Cb/Cr)',
              value: params.chrominanceTolerance.toDouble(),
              min: 10,
              max: 80,
              divisions: 14,
              onChanged: (v) => onParamsChanged(
                params.copyWith(chrominanceTolerance: v.toInt()),
              ),
            ),
            _buildSlider(
              label: '牌の縦横比 (W/H)',
              value: params.tileAspectRatio,
              min: 0.5,
              max: 1.0,
              divisions: 20,
              onChanged: (v) => onParamsChanged(
                params.copyWith(tileAspectRatio: v),
              ),
            ),
            _buildSlider(
              label: '投影しきい値 (%)',
              value: params.projectionThreshold,
              min: 0.05,
              max: 0.50,
              divisions: 18,
              onChanged: (v) => onParamsChanged(
                params.copyWith(projectionThreshold: v),
              ),
            ),
            _buildSlider(
              label: 'スキャン上端',
              value: params.scanRegionTop,
              min: 0.0,
              max: 0.8,
              divisions: 16,
              onChanged: (v) => onParamsChanged(
                params.copyWith(
                  scanRegionTop: v,
                  // Enforce top < bottom
                  scanRegionBottom: v >= params.scanRegionBottom
                      ? (v + 0.1).clamp(0.1, 1.0)
                      : null,
                ),
              ),
            ),
            _buildSlider(
              label: 'スキャン下端',
              value: params.scanRegionBottom,
              min: 0.2,
              max: 1.0,
              divisions: 16,
              onChanged: (v) => onParamsChanged(
                params.copyWith(
                  scanRegionBottom: v,
                  // Enforce top < bottom
                  scanRegionTop: v <= params.scanRegionTop
                      ? (v - 0.1).clamp(0.0, 0.9)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultSummary(TileDetectorResult result) {
    final isMatch = result.tileCount == TileDetector.targetTileCount;
    final axisLabel = result.axis == ScanAxis.horizontal ? '横' : '縦';

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _chip(
                '検出数: ${result.tileCount}',
                isMatch ? Colors.green : Colors.white24,
              ),
              const SizedBox(width: 6),
              _chip('軸: $axisLabel', Colors.white24),
              const SizedBox(width: 6),
              _chip('帯長: ${result.bandLength}px', Colors.white24),
              const SizedBox(width: 6),
              _chip('帯厚: ${result.bandThickness}px', Colors.white24),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '1牌幅: ${result.estimatedTileWidth.toStringAsFixed(1)}px'
            '  (${result.bandLength} ÷ ${result.estimatedTileWidth.toStringAsFixed(1)}'
            ' = ${result.tileCount})',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            '位置: (${result.bandLeft}, ${result.bandTop})'
            '  スパン: ${result.bandSpanWidth}×${result.bandSpanHeight}'
            '  画像: ${result.imageWidth}×${result.imageHeight}',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAxisComparison() {
    String line(String label, TileDetectorResult? r) {
      if (r == null) return '$label: --';
      return '$label: ${r.tileCount}枚'
          '  帯${r.bandLength}×${r.bandThickness}'
          '  span${r.bandSpanWidth}×${r.bandSpanHeight}';
    }

    final selected = lastResult?.axis == ScanAxis.horizontal ? '横' : '縦';
    return Text(
      '${line("横", hResult)}\n'
      '${line("縦", vResult)}\n'
      '→ 採用: $selected',
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 9,
        fontFamily: 'monospace',
        height: 1.4,
      ),
    );
  }

  Widget _chip(String text, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    // Clamp value to slider range to prevent crash
    final clampedValue = value.clamp(min, max);
    final isInt = min == min.roundToDouble() && max == max.roundToDouble();
    final displayValue = isInt
        ? clampedValue.toInt().toString()
        : clampedValue.toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                trackHeight: 2,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: clampedValue,
                min: min,
                max: max,
                divisions: divisions,
                activeColor: Colors.amberAccent,
                inactiveColor: Colors.white24,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              displayValue,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
