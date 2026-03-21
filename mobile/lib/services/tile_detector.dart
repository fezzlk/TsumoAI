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
  final double projectionThreshold;

  const TileDetectorParams({
    this.luminanceMin = 140,
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

/// A rectangle in image coordinates (before rotation/scaling).
class TileRect {
  final double left;
  final double top;
  final double width;
  final double height;
  const TileRect({required this.left, required this.top, required this.width, required this.height});
}

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

  /// Per-tile bounding rects in image coordinates.
  final List<TileRect> tileRects;

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
    this.tileRects = const [],
  });
}

/// On-device tile detector using connected-component analysis.
///
/// Works with any tile arrangement (horizontal row, vertical stack, scattered).
///
/// Algorithm:
/// 1. Build a downsampled white-pixel mask from the camera YUV frame
/// 2. Find connected components via flood fill
/// 3. Filter by area and density to reject noise
/// 4. Subdivide oversized components using tile aspect ratio
class TileDetector {
  static const int targetTileCount = 14;

  /// Downscale factor for the white-pixel mask (4 = 1/4 resolution).
  static const int _scale = 4;

  /// Minimum component area in downscaled pixels.
  static const int _minComponentArea = 30;

  static Future<TileDetectorResult> detect(
    CameraImage image, [
    TileDetectorParams params = const TileDetectorParams(),
  ]) {
    return compute(_analyzeIsolate, _buildInput(image, params));
  }

  static Future<int> countTiles(
    CameraImage image, [
    TileDetectorParams params = const TileDetectorParams(),
  ]) async {
    return (await detect(image, params)).tileCount;
  }

  /// Returns both axis results for debug display.
  /// With component-based detection, h/v/best are all the same result.
  static Future<({TileDetectorResult h, TileDetectorResult v, TileDetectorResult best})> detectBoth(
    CameraImage image, [
    TileDetectorParams params = const TileDetectorParams(),
  ]) {
    return compute(_analyzeBothIsolate, _buildInput(image, params));
  }

  static _AnalysisInput _buildInput(CameraImage image, TileDetectorParams params) {
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

    return _AnalysisInput(
      yBytes: Uint8List.fromList(yPlane.bytes),
      uvBytes: uvBytes,
      vBytes: vBytes,
      width: image.width,
      height: image.height,
      yBytesPerRow: yPlane.bytesPerRow,
      uvBytesPerRow: uvBytesPerRow,
      uvPixelStride: uvPixelStride,
      params: params,
    );
  }

  static ({TileDetectorResult h, TileDetectorResult v, TileDetectorResult best}) _analyzeBothIsolate(_AnalysisInput input) {
    final result = _detectByComponents(input);
    return (h: result, v: result, best: result);
  }

  static TileDetectorResult _analyzeIsolate(_AnalysisInput input) {
    return _detectByComponents(input);
  }

  // ───────── Connected-component detection ─────────

  static TileDetectorResult _detectByComponents(_AnalysisInput input) {
    final imgW = input.width;
    final imgH = input.height;

    final empty = TileDetectorResult(
      tileCount: 0, bandLength: 0, bandThickness: 0,
      estimatedTileWidth: 0, axis: ScanAxis.horizontal,
      imageWidth: imgW, imageHeight: imgH,
    );

    // Scan region
    final top = input.params.scanRegionTop.clamp(0.0, 0.95);
    final bottom = input.params.scanRegionBottom.clamp(top + 0.05, 1.0);
    final scanYStart = (imgH * top).toInt();
    final scanYEnd = (imgH * bottom).toInt();

    // Build downsampled white pixel mask
    final mW = imgW ~/ _scale;
    final scanMYStart = scanYStart ~/ _scale;
    final scanMYEnd = scanYEnd ~/ _scale;
    final mH = scanMYEnd - scanMYStart;
    if (mW <= 0 || mH <= 0) return empty;

    // Build white pixel mask
    final rawMask = Uint8List(mH * mW);
    for (int my = 0; my < mH; my++) {
      for (int mx = 0; mx < mW; mx++) {
        if (_isWhitePixel(input, mx * _scale, (my + scanMYStart) * _scale)) {
          rawMask[my * mW + mx] = 1;
        }
      }
    }

    // Morphological close (dilate then erode) to bridge gaps within tile faces
    // caused by colored patterns breaking up the white region
    final dilated = Uint8List(mH * mW);
    for (int y = 0; y < mH; y++) {
      for (int x = 0; x < mW; x++) {
        if (rawMask[y * mW + x] == 1) {
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              final ny = y + dy, nx = x + dx;
              if (ny >= 0 && ny < mH && nx >= 0 && nx < mW) {
                dilated[ny * mW + nx] = 1;
              }
            }
          }
        }
      }
    }
    final mask = Uint8List(mH * mW);
    for (int y = 0; y < mH; y++) {
      for (int x = 0; x < mW; x++) {
        final idx = y * mW + x;
        if (dilated[idx] == 0) continue;
        bool allSet = true;
        for (int dy = -1; dy <= 1 && allSet; dy++) {
          for (int dx = -1; dx <= 1 && allSet; dx++) {
            final ny = y + dy, nx = x + dx;
            if (ny < 0 || ny >= mH || nx < 0 || nx >= mW || dilated[ny * mW + nx] == 0) {
              allSet = false;
            }
          }
        }
        if (allSet) mask[idx] = 1;
      }
    }

    // Connected component labeling via flood fill (8-connected)
    final labels = Int32List(mH * mW);
    int nextLabel = 0;
    // Each component: [minX, minY, maxX, maxY, pixelCount]
    final components = <List<int>>[];

    for (int y = 0; y < mH; y++) {
      for (int x = 0; x < mW; x++) {
        final idx = y * mW + x;
        if (mask[idx] != 1 || labels[idx] != 0) continue;

        nextLabel++;
        int minX = x, maxX = x, minY = y, maxY = y, count = 0;
        final stack = <int>[idx];
        labels[idx] = nextLabel;

        while (stack.isNotEmpty) {
          final ci = stack.removeLast();
          final cx = ci % mW;
          final cy = ci ~/ mW;
          count++;
          if (cx < minX) minX = cx;
          if (cx > maxX) maxX = cx;
          if (cy < minY) minY = cy;
          if (cy > maxY) maxY = cy;

          // 8-connected neighbors
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              if (dy == 0 && dx == 0) continue;
              final nx = cx + dx, ny = cy + dy;
              if (nx >= 0 && nx < mW && ny >= 0 && ny < mH) {
                final ni = ny * mW + nx;
                if (mask[ni] == 1 && labels[ni] == 0) {
                  labels[ni] = nextLabel;
                  stack.add(ni);
                }
              }
            }
          }
        }

        components.add([minX, minY, maxX, maxY, count]);
      }
    }

    if (components.isEmpty) return empty;

    // Filter components by absolute size and max size
    // Min: reject noise. Max: reject huge surfaces (table, towel)
    final maxComponentArea = (mH * mW * 0.05).toInt(); // 5% of image = too large for tiles

    final filtered = <List<int>>[];
    for (final c in components) {
      final count = c[4];
      if (count < _minComponentArea) continue;
      if (count > maxComponentArea) continue;
      final bw = c[2] - c[0] + 1;
      final bh = c[3] - c[1] + 1;
      final bboxArea = bw * bh;
      if (bboxArea == 0 || count / bboxArea < 0.20) continue;
      filtered.add(c);
    }

    if (filtered.isEmpty) return empty;

    // Build tile rects, subdividing oversized components by aspect ratio
    final tileAspect = input.params.tileAspectRatio;
    final tileRects = <TileRect>[];

    for (final c in filtered) {
      final bw = (c[2] - c[0] + 1) * _scale;
      final bh = (c[3] - c[1] + 1) * _scale;
      final ox = c[0] * _scale.toDouble();
      final oy = (c[1] + scanMYStart) * _scale.toDouble();

      if (bw >= bh) {
        // Wider or square: possibly side-by-side tiles
        final expectedTileW = bh * tileAspect;
        final nSub = expectedTileW > 0 ? (bw / expectedTileW).round().clamp(1, 20) : 1;
        final subW = bw / nSub;
        for (int i = 0; i < nSub; i++) {
          tileRects.add(TileRect(left: ox + i * subW, top: oy, width: subW, height: bh.toDouble()));
        }
      } else {
        // Taller: possibly stacked tiles
        final expectedTileH = bw / tileAspect;
        final nSub = expectedTileH > 0 ? (bh / expectedTileH).round().clamp(1, 20) : 1;
        final subH = bh / nSub;
        for (int i = 0; i < nSub; i++) {
          tileRects.add(TileRect(left: ox, top: oy + i * subH, width: bw.toDouble(), height: subH));
        }
      }
    }

    if (tileRects.isEmpty) return empty;

    // Compute band-level stats for backward compatibility
    double minBX = double.infinity, minBY = double.infinity;
    double maxBX = 0, maxBY = 0;
    double totalW = 0, totalH = 0;
    for (final r in tileRects) {
      if (r.left < minBX) minBX = r.left;
      if (r.top < minBY) minBY = r.top;
      if (r.left + r.width > maxBX) maxBX = r.left + r.width;
      if (r.top + r.height > maxBY) maxBY = r.top + r.height;
      totalW += r.width;
      totalH += r.height;
    }
    final avgW = totalW / tileRects.length;
    final avgH = totalH / tileRects.length;
    final spanX = maxBX - minBX;
    final spanY = maxBY - minBY;
    final axis = spanX >= spanY ? ScanAxis.horizontal : ScanAxis.vertical;

    return TileDetectorResult(
      tileCount: tileRects.length,
      bandLength: (axis == ScanAxis.horizontal ? spanX : spanY).toInt(),
      bandThickness: (axis == ScanAxis.horizontal ? avgH : avgW).toInt(),
      estimatedTileWidth: axis == ScanAxis.horizontal ? avgW : avgH,
      axis: axis,
      bandLeft: minBX.toInt(),
      bandTop: minBY.toInt(),
      bandSpanWidth: spanX.toInt(),
      bandSpanHeight: spanY.toInt(),
      imageWidth: imgW,
      imageHeight: imgH,
      tileRects: tileRects,
    );
  }

  // ───────── Helpers ─────────

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
