import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Tunable parameters for tile detection.
class TileDetectorParams {
  /// Minimum Y (luminance) to consider a pixel as "white tile"
  final int luminanceMin;

  /// Maximum deviation from 128 for Cb/Cr to be considered "white" (low saturation)
  final int chrominanceTolerance;

  /// Top of scan region as fraction of image size (0.0 - 1.0)
  final double scanRegionTop;

  /// Bottom of scan region as fraction of image size (0.0 - 1.0)
  final double scanRegionBottom;

  /// Width-to-height aspect ratio of a single tile face (standard ≈ 0.75)
  final double tileAspectRatio;

  /// Fraction of the peak projection value used as threshold.
  /// E.g. 0.3 means a column/row needs at least 30% of the peak's
  /// white-pixel count to be considered part of the tile region.
  final double projectionThreshold;

  const TileDetectorParams({
    this.luminanceMin = 160,
    this.chrominanceTolerance = 45,
    this.scanRegionTop = 0.05,
    this.scanRegionBottom = 0.95,
    this.tileAspectRatio = 0.75,
    this.projectionThreshold = 0.30,
  });

  TileDetectorParams copyWith({
    int? luminanceMin,
    int? chrominanceTolerance,
    double? scanRegionTop,
    double? scanRegionBottom,
    double? tileAspectRatio,
    double? projectionThreshold,
  }) {
    return TileDetectorParams(
      luminanceMin: luminanceMin ?? this.luminanceMin,
      chrominanceTolerance: chrominanceTolerance ?? this.chrominanceTolerance,
      scanRegionTop: scanRegionTop ?? this.scanRegionTop,
      scanRegionBottom: scanRegionBottom ?? this.scanRegionBottom,
      tileAspectRatio: tileAspectRatio ?? this.tileAspectRatio,
      projectionThreshold: projectionThreshold ?? this.projectionThreshold,
    );
  }
}

/// Scan axis used for detection.
enum ScanAxis { horizontal, vertical }

/// Result of tile detection including position data for overlay.
class TileDetectorResult {
  final int tileCount;

  /// Total white pixels along the main axis (sum of all tile regions).
  final int bandLength;

  /// Thickness of the tile band (perpendicular to tile row).
  final int bandThickness;

  /// Estimated width of a single tile (pixels).
  final double estimatedTileWidth;

  /// Which axis produced this result.
  final ScanAxis axis;

  /// Band bounding box in image coordinates (covers all detected tiles).
  final int bandLeft;
  final int bandTop;
  /// Full span from first to last detected tile pixel.
  final int bandSpanWidth;
  final int bandSpanHeight;

  /// Source image dimensions (for coordinate mapping).
  final int imageWidth;
  final int imageHeight;

  const TileDetectorResult({
    required this.tileCount,
    required this.bandLength,
    required this.bandThickness,
    required this.estimatedTileWidth,
    required this.axis,
    this.bandLeft = 0,
    this.bandTop = 0,
    this.bandSpanWidth = 0,
    this.bandSpanHeight = 0,
    this.imageWidth = 0,
    this.imageHeight = 0,
  });
}

/// On-device tile counter optimized for white tiles on a green mat.
///
/// Uses histogram projection with **adaptive threshold** (fraction of peak).
/// This handles tiles that occupy only a small fraction of the image.
///
/// Algorithm:
/// 1. Compute main-axis projection (white pixel count per column/row)
/// 2. Threshold = peak value × projectionThreshold
/// 3. Sum all regions above threshold = total tile length
/// 4. Measure cross-axis thickness for the largest region
/// 5. tile_count = total_length / (thickness × aspect_ratio)
class TileDetector {
  static const int targetTileCount = 14;

  static Future<TileDetectorResult> detect(
    CameraImage image, [
    TileDetectorParams params = const TileDetectorParams(),
  ]) {
    final yPlane = image.planes[0];

    Uint8List? uvBytes;
    Uint8List? vBytes;
    int uvBytesPerRow = 0;
    int uvPixelStride = 1;

    if (image.planes.length >= 2) {
      final uvPlane = image.planes[1];
      uvBytes = Uint8List.fromList(uvPlane.bytes);
      uvBytesPerRow = uvPlane.bytesPerRow;
      uvPixelStride = uvPlane.bytesPerPixel ?? 1;

      if (image.planes.length >= 3 && uvPixelStride == 1) {
        vBytes = Uint8List.fromList(image.planes[2].bytes);
      }
    }

    return compute(_analyzeIsolate, _AnalysisInput(
      yBytes: Uint8List.fromList(yPlane.bytes),
      uvBytes: uvBytes,
      vBytes: vBytes,
      width: image.width,
      height: image.height,
      yBytesPerRow: yPlane.bytesPerRow,
      uvBytesPerRow: uvBytesPerRow,
      uvPixelStride: uvPixelStride,
      params: params,
    ));
  }

  static Future<int> countTiles(
    CameraImage image, [
    TileDetectorParams params = const TileDetectorParams(),
  ]) async {
    return (await detect(image, params)).tileCount;
  }

  /// Returns both axis results for debug display.
  static Future<({TileDetectorResult h, TileDetectorResult v, TileDetectorResult best})> detectBoth(
    CameraImage image, [
    TileDetectorParams params = const TileDetectorParams(),
  ]) {
    final yPlane = image.planes[0];

    Uint8List? uvBytes;
    Uint8List? vBytes;
    int uvBytesPerRow = 0;
    int uvPixelStride = 1;

    if (image.planes.length >= 2) {
      final uvPlane = image.planes[1];
      uvBytes = Uint8List.fromList(uvPlane.bytes);
      uvBytesPerRow = uvPlane.bytesPerRow;
      uvPixelStride = uvPlane.bytesPerPixel ?? 1;
      if (image.planes.length >= 3 && uvPixelStride == 1) {
        vBytes = Uint8List.fromList(image.planes[2].bytes);
      }
    }

    return compute(_analyzeBothIsolate, _AnalysisInput(
      yBytes: Uint8List.fromList(yPlane.bytes),
      uvBytes: uvBytes,
      vBytes: vBytes,
      width: image.width,
      height: image.height,
      yBytesPerRow: yPlane.bytesPerRow,
      uvBytesPerRow: uvBytesPerRow,
      uvPixelStride: uvPixelStride,
      params: params,
    ));
  }

  static ({TileDetectorResult h, TileDetectorResult v, TileDetectorResult best}) _analyzeBothIsolate(_AnalysisInput input) {
    final h = _scanDirection(input, ScanAxis.horizontal);
    final v = _scanDirection(input, ScanAxis.vertical);
    final hDiff = (h.tileCount - targetTileCount).abs();
    final vDiff = (v.tileCount - targetTileCount).abs();
    TileDetectorResult best;
    if (hDiff < vDiff) {
      best = h;
    } else if (vDiff < hDiff) {
      best = v;
    } else {
      best = h.bandLength >= v.bandLength ? h : v;
    }
    return (h: h, v: v, best: best);
  }

  // ───────── Isolate entry point ─────────

  static TileDetectorResult _analyzeIsolate(_AnalysisInput input) {
    final hResult = _scanDirection(input, ScanAxis.horizontal);
    final vResult = _scanDirection(input, ScanAxis.vertical);

    // Pick whichever axis gives a count closer to the target.
    // Tie-break: prefer the axis with more total tile pixels.
    final hDiff = (hResult.tileCount - targetTileCount).abs();
    final vDiff = (vResult.tileCount - targetTileCount).abs();

    if (hDiff < vDiff) return hResult;
    if (vDiff < hDiff) return vResult;
    return hResult.bandLength >= vResult.bandLength ? hResult : vResult;
  }

  // ───────── Histogram-based scan ─────────

  static TileDetectorResult _scanDirection(_AnalysisInput input, ScanAxis axis) {
    final imgW = input.width;
    final imgH = input.height;

    final mainSize = axis == ScanAxis.horizontal ? imgW : imgH;
    final crossSize = axis == ScanAxis.horizontal ? imgH : imgW;

    final top = input.params.scanRegionTop.clamp(0.0, 0.95);
    final bottom = input.params.scanRegionBottom.clamp(top + 0.05, 1.0);
    final crossStart = (crossSize * top).toInt();
    final crossEnd = (crossSize * bottom).toInt();
    final crossSpan = crossEnd - crossStart;

    final empty = TileDetectorResult(
      tileCount: 0, bandLength: 0, bandThickness: 0,
      estimatedTileWidth: 0, axis: axis,
      imageWidth: imgW, imageHeight: imgH,
    );
    if (crossSpan <= 0 || mainSize <= 0) return empty;

    // ── Step 1: Main-axis projection ──
    // For each position along main axis, count white pixels along cross axis.
    final mainProj = List.filled(mainSize, 0);
    const crossStep = 3; // sample every 3rd pixel for speed
    for (int c = crossStart; c < crossEnd; c += crossStep) {
      for (int m = 0; m < mainSize; m++) {
        final x = axis == ScanAxis.horizontal ? m : c;
        final y = axis == ScanAxis.horizontal ? c : m;
        if (_isWhitePixel(input, x, y)) {
          mainProj[m]++;
        }
      }
    }

    // ── Step 2: Adaptive threshold from peak ──
    int peak = 0;
    for (final v in mainProj) {
      if (v > peak) peak = v;
    }
    if (peak < 3) return empty; // no significant white region found

    final threshold = (peak * input.params.projectionThreshold).toInt();

    // ── Step 3: Find all regions above threshold ──
    final plateaus = _findAllPlateaus(mainProj, threshold);
    if (plateaus.isEmpty) return empty;

    // Total tile pixels = sum of all plateau lengths
    int totalLength = 0;
    int firstStart = plateaus.first.start;
    int lastEnd = plateaus.last.start + plateaus.last.length;
    _Run largest = plateaus.first;
    for (final p in plateaus) {
      totalLength += p.length;
      if (p.length > largest.length) largest = p;
    }

    if (totalLength < 10) return empty;

    // ── Step 4: Cross-axis projection within the largest plateau ──
    // Use the largest plateau to measure tile thickness (height).
    final crossProj = List.filled(crossSpan, 0);
    const mainStep = 3;
    int peakCross = 0;
    for (int m = largest.start; m < largest.start + largest.length; m += mainStep) {
      for (int c = crossStart; c < crossEnd; c++) {
        final x = axis == ScanAxis.horizontal ? m : c;
        final y = axis == ScanAxis.horizontal ? c : m;
        if (_isWhitePixel(input, x, y)) {
          crossProj[c - crossStart]++;
          if (crossProj[c - crossStart] > peakCross) {
            peakCross = crossProj[c - crossStart];
          }
        }
      }
    }

    if (peakCross < 2) return empty;
    final crossThreshold = (peakCross * input.params.projectionThreshold).toInt();
    final crossPlateaus = _findAllPlateaus(crossProj, crossThreshold);
    if (crossPlateaus.isEmpty) return empty;

    // Use the largest cross-plateau as tile thickness
    _Run largestCross = crossPlateaus.first;
    for (final p in crossPlateaus) {
      if (p.length > largestCross.length) largestCross = p;
    }
    final bandThickness = largestCross.length;

    if (bandThickness <= 0) return empty;

    // ── Step 5: Estimate tile count ──
    final estTileW = bandThickness * input.params.tileAspectRatio;
    final count = estTileW > 0 ? (totalLength / estTileW).round() : 0;

    // Band bounding box for overlay
    final crossAbsStart = crossStart + largestCross.start;
    final bandLeft = axis == ScanAxis.horizontal ? firstStart : crossAbsStart;
    final bandTop = axis == ScanAxis.horizontal ? crossAbsStart : firstStart;
    final spanMain = lastEnd - firstStart;
    final bandSpanW = axis == ScanAxis.horizontal ? spanMain : bandThickness;
    final bandSpanH = axis == ScanAxis.horizontal ? bandThickness : spanMain;

    return TileDetectorResult(
      tileCount: count,
      bandLength: totalLength,
      bandThickness: bandThickness,
      estimatedTileWidth: estTileW,
      axis: axis,
      bandLeft: bandLeft,
      bandTop: bandTop,
      bandSpanWidth: bandSpanW,
      bandSpanHeight: bandSpanH,
      imageWidth: imgW,
      imageHeight: imgH,
    );
  }

  // ───────── Helpers ─────────

  /// Find ALL contiguous regions in [proj] where values >= [threshold].
  static List<_Run> _findAllPlateaus(List<int> proj, int threshold) {
    final results = <_Run>[];
    int curStart = -1;
    int curLen = 0;

    for (int i = 0; i < proj.length; i++) {
      if (proj[i] >= threshold) {
        if (curStart < 0) curStart = i;
        curLen++;
      } else {
        if (curLen > 0) {
          results.add(_Run(start: curStart, length: curLen));
        }
        curStart = -1;
        curLen = 0;
      }
    }
    if (curLen > 0) {
      results.add(_Run(start: curStart, length: curLen));
    }
    return results;
  }

  /// Check if a pixel is "white" (high luminance, neutral chrominance).
  static bool _isWhitePixel(_AnalysisInput input, int x, int y) {
    if (x < 0 || x >= input.width || y < 0 || y >= input.height) {
      return false;
    }

    final yOffset = y * input.yBytesPerRow + x;
    if (yOffset < 0 || yOffset >= input.yBytes.length) {
      return false;
    }
    if (input.yBytes[yOffset] < input.params.luminanceMin) {
      return false;
    }

    if (input.uvBytes == null) return true;

    final uvX = x ~/ 2;
    final uvY = y ~/ 2;
    final uvOffset = uvY * input.uvBytesPerRow + uvX * input.uvPixelStride;
    if (uvOffset < 0 || uvOffset >= input.uvBytes!.length) return true;

    int cb, cr;
    if (input.vBytes != null) {
      if (uvOffset >= input.vBytes!.length) return true;
      cb = input.uvBytes![uvOffset];
      cr = input.vBytes![uvOffset];
    } else if (input.uvPixelStride >= 2) {
      if (uvOffset + 1 >= input.uvBytes!.length) return true;
      cb = input.uvBytes![uvOffset];
      cr = input.uvBytes![uvOffset + 1];
    } else {
      return true;
    }

    final tol = input.params.chrominanceTolerance;
    if ((cb - 128).abs() > tol || (cr - 128).abs() > tol) {
      return false;
    }
    return true;
  }
}

class _Run {
  final int start;
  final int length;
  const _Run({required this.start, required this.length});
}

class _AnalysisInput {
  final Uint8List yBytes;
  final Uint8List? uvBytes;
  final Uint8List? vBytes;
  final int width;
  final int height;
  final int yBytesPerRow;
  final int uvBytesPerRow;
  final int uvPixelStride;
  final TileDetectorParams params;

  _AnalysisInput({
    required this.yBytes,
    this.uvBytes,
    this.vBytes,
    required this.width,
    required this.height,
    required this.yBytesPerRow,
    required this.uvBytesPerRow,
    required this.uvPixelStride,
    required this.params,
  });
}
