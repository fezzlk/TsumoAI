// On-device tile segmentation: given a photo of a mahjong hand, find the
// pixel-space bounding box of each individual tile.
//
// This mirrors `app/tile_recognizer_local.py`'s `_segment_tiles` (server
// side, Python) 1:1, including the joint 13/14-tile hand-size constraint
// used to resolve ambiguity no single blob's own periodicity signal can
// resolve alone (harmonic-locked autocorrelation, or a blob with no
// periodicity of its own such as an unrelated object in frame). See that
// file for the derivation/validation of this approach (case-003/006
// regression cases).

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart' show Rect;
import 'package:image/image.dart' as img;

typedef _Comp = ({int x, int y, int w, int h, int area});

/// Detect individual tile bounding boxes in [image]. Returns boxes in
/// [image]'s own pixel coordinate space (not downscaled). Empty if no
/// plausible tile run is found.
List<Rect> segmentTiles(img.Image image) {
  const scale = 4;
  final w = image.width;
  final h = image.height;
  final mW = w ~/ scale;
  final mH = h ~/ scale;
  if (mW <= 0 || mH <= 0) return [];

  // Raw white-pixel mask (pre-morphology; kept for pitch detection, since
  // CLOSE bridges the thin gaps between touching tiles).
  final maskRaw = Uint8List(mW * mH);
  for (int my = 0; my < mH; my++) {
    for (int mx = 0; mx < mW; mx++) {
      if (_isWhitePixel(image, mx * scale, my * scale)) {
        maskRaw[my * mW + mx] = 1;
      }
    }
  }

  // Morphological cleanup (component-finding only): CLOSE then OPEN, 5x5.
  final closed = _erodeRect(_dilateRect(maskRaw, mW, mH, 2), mW, mH, 2);
  final mask = _dilateRect(_erodeRect(closed, mW, mH, 2), mW, mH, 2);

  // Connected components (8-connected flood fill).
  final labels = Int32List(mW * mH);
  int nextLabel = 0;
  final components = <_Comp>[];

  for (int y = 0; y < mH; y++) {
    for (int x = 0; x < mW; x++) {
      final idx = y * mW + x;
      if (mask[idx] == 0 || labels[idx] != 0) continue;

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

        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dy == 0 && dx == 0) continue;
            final nx = cx + dx, ny = cy + dy;
            if (nx >= 0 && nx < mW && ny >= 0 && ny < mH) {
              final ni = ny * mW + nx;
              if (mask[ni] != 0 && labels[ni] == 0) {
                labels[ni] = nextLabel;
                stack.add(ni);
              }
            }
          }
        }
      }

      components.add((x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1, area: count));
    }
  }

  if (components.isEmpty) return [];

  final maskArea = mW * mH;
  final minArea = math.max(300 / (scale * scale), 0.003 * maskArea);
  final minDimW = 0.015 * mW;
  final minDimH = 0.015 * mH;

  final filtered = <_Comp>[];
  for (final c in components) {
    if (c.area < minArea || c.w < minDimW || c.h < minDimH) continue;
    final bboxArea = c.w * c.h;
    if (bboxArea == 0 || c.area / bboxArea < 0.20) continue;
    filtered.add(c);
  }
  if (filtered.isEmpty) return [];

  // Decide run orientation once, from how ALL surviving components are
  // spatially arranged (not any single component's own aspect ratio).
  int spanMinX = filtered.first.x, spanMaxX = filtered.first.x + filtered.first.w;
  int spanMinY = filtered.first.y, spanMaxY = filtered.first.y + filtered.first.h;
  for (final c in filtered) {
    if (c.x < spanMinX) spanMinX = c.x;
    if (c.x + c.w > spanMaxX) spanMaxX = c.x + c.w;
    if (c.y < spanMinY) spanMinY = c.y;
    if (c.y + c.h > spanMaxY) spanMaxY = c.y + c.h;
  }
  final vertical = (spanMaxY - spanMinY) >= (spanMaxX - spanMinX);

  // Drop components whose extent along the run axis substantially overlaps
  // an already-kept larger component (glare/reflection noise).
  final sortedByArea = [...filtered]..sort((a, b) => b.area.compareTo(a.area));
  final kept = <_Comp>[];
  for (final c in sortedByArea) {
    final lo = vertical ? c.y : c.x;
    final hi = vertical ? c.y + c.h : c.x + c.w;
    final span = hi - lo;
    bool overlap = false;
    for (final k in kept) {
      final klo = vertical ? k.y : k.x;
      final khi = vertical ? k.y + k.h : k.x + k.w;
      final inter = math.max(0, math.min(hi, khi) - math.max(lo, klo));
      if (span > 0 && inter / span > 0.5) {
        overlap = true;
        break;
      }
    }
    if (!overlap) kept.add(c);
  }
  kept.sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));

  // Estimate each blob's own pitch, then resolve tile counts jointly using
  // the 13/14-tile hand-size constraint.
  final blobPitches = <(int?, double, int)>[
    for (final c in kept) _blobPitch(maskRaw, mW, c.x, c.y, c.w, c.h, vertical),
  ];
  final dims = [for (final bp in blobPitches) bp.$3.toDouble()];
  final tileCounts = _resolveTileCounts(dims, blobPitches);

  // Subdivide each kept component into individual tiles, scaling back up
  // to the original image's pixel coordinate space.
  final result = <Rect>[];
  for (int i = 0; i < kept.length; i++) {
    final n = tileCounts[i];
    if (n <= 0) continue;
    final c = kept[i];
    if (vertical) {
      final subH = c.h / n;
      for (int j = 0; j < n; j++) {
        final sy = c.y + (j * subH).toInt();
        final ey = c.y + ((j + 1) * subH).toInt();
        result.add(Rect.fromLTWH(
          (c.x * scale).toDouble(),
          (sy * scale).toDouble(),
          (c.w * scale).toDouble(),
          ((ey - sy) * scale).toDouble(),
        ));
      }
    } else {
      final subW = c.w / n;
      for (int j = 0; j < n; j++) {
        final sx = c.x + (j * subW).toInt();
        final ex = c.x + ((j + 1) * subW).toInt();
        result.add(Rect.fromLTWH(
          (sx * scale).toDouble(),
          (c.y * scale).toDouble(),
          ((ex - sx) * scale).toDouble(),
          (c.h * scale).toDouble(),
        ));
      }
    }
  }
  return result;
}

/// Decode [bytes] and run [segmentTiles]. Suitable as a top-level `compute()`
/// isolate entry point (decoding happens inside the isolate to avoid
/// transferring a decoded `img.Image` across the isolate boundary).
List<Rect> segmentTilesFromBytes(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return [];
  final rgb = decoded.numChannels == 3 ? decoded : decoded.convert(numChannels: 3);
  return segmentTiles(rgb);
}

// ───────── White-pixel test (RGB, low saturation / high value) ─────────

bool _isWhitePixel(img.Image image, int x, int y) {
  final px = image.getPixel(x, y);
  final r = px.r.toInt(), g = px.g.toInt(), b = px.b.toInt();
  final maxC = math.max(r, math.max(g, b));
  final minC = math.min(r, math.min(g, b));
  final sat = maxC > 0 ? ((maxC - minC) * 255) ~/ maxC : 0;
  return maxC >= 160 && sat <= 80;
}

// ───────── Morphology: separable square dilate/erode ─────────

Uint8List _dilateRect(Uint8List mask, int w, int h, int radius) {
  final tmp = Uint8List(w * h);
  for (int y = 0; y < h; y++) {
    final rowOff = y * w;
    for (int x = 0; x < w; x++) {
      final lo = math.max(0, x - radius), hi = math.min(w - 1, x + radius);
      int v = 0;
      for (int xx = lo; xx <= hi; xx++) {
        if (mask[rowOff + xx] != 0) {
          v = 1;
          break;
        }
      }
      tmp[rowOff + x] = v;
    }
  }
  final out = Uint8List(w * h);
  for (int x = 0; x < w; x++) {
    for (int y = 0; y < h; y++) {
      final lo = math.max(0, y - radius), hi = math.min(h - 1, y + radius);
      int v = 0;
      for (int yy = lo; yy <= hi; yy++) {
        if (tmp[yy * w + x] != 0) {
          v = 1;
          break;
        }
      }
      out[y * w + x] = v;
    }
  }
  return out;
}

Uint8List _erodeRect(Uint8List mask, int w, int h, int radius) {
  final tmp = Uint8List(w * h);
  for (int y = 0; y < h; y++) {
    final rowOff = y * w;
    for (int x = 0; x < w; x++) {
      final lo = math.max(0, x - radius), hi = math.min(w - 1, x + radius);
      int v = 1;
      for (int xx = lo; xx <= hi; xx++) {
        if (mask[rowOff + xx] == 0) {
          v = 0;
          break;
        }
      }
      tmp[rowOff + x] = v;
    }
  }
  final out = Uint8List(w * h);
  for (int x = 0; x < w; x++) {
    for (int y = 0; y < h; y++) {
      final lo = math.max(0, y - radius), hi = math.min(h - 1, y + radius);
      int v = 1;
      for (int yy = lo; yy <= hi; yy++) {
        if (tmp[yy * w + x] == 0) {
          v = 0;
          break;
        }
      }
      out[y * w + x] = v;
    }
  }
  return out;
}

// ───────── Autocorrelation-based pitch detection ─────────

List<int> _findLocalMaxima(List<double> seg, {double prominence = 0.02}) {
  final peaks = <int>[];
  for (int i = 1; i < seg.length - 1; i++) {
    if (seg[i] > seg[i - 1] && seg[i] >= seg[i + 1]) {
      final leftStart = math.max(0, i - 10);
      double leftMin = seg[leftStart];
      for (int k = leftStart; k < i; k++) {
        if (seg[k] < leftMin) leftMin = seg[k];
      }
      double rightMin;
      if (i + 1 < seg.length) {
        final rightEnd = math.min(seg.length, i + 11);
        rightMin = seg[i + 1];
        for (int k = i + 1; k < rightEnd; k++) {
          if (seg[k] < rightMin) rightMin = seg[k];
        }
      } else {
        rightMin = seg[i];
      }
      if (seg[i] - math.max(leftMin, rightMin) >= prominence) {
        peaks.add(i);
      }
    }
  }
  return peaks;
}

/// Detect the repeat period (tile pitch) in a 1-D white-fraction [profile]
/// via autocorrelation. Returns (pitch_px, confidence), or (null, 0.0) if no
/// genuine interior periodicity is found (i.e. this blob is a single tile).
(int?, double) _estimatePitch(List<double> profile, int dim) {
  final n = profile.length;
  if (n == 0) return (null, 0.0);
  double mean = 0;
  for (final v in profile) {
    mean += v;
  }
  mean /= n;
  final sig = List<double>.generate(n, (i) => profile[i] - mean);
  double variance = 0;
  for (final v in sig) {
    variance += v * v;
  }
  if (math.sqrt(variance / n) < 1e-6) return (null, 0.0);

  final ac = List<double>.filled(n, 0.0);
  for (int lag = 0; lag < n; lag++) {
    double s = 0;
    for (int i = 0; i < n - lag; i++) {
      s += sig[i] * sig[i + lag];
    }
    ac[lag] = s;
  }
  if (ac[0] <= 0) return (null, 0.0);
  final acNorm = List<double>.generate(n, (i) => ac[i] / ac[0]);

  final lo = math.max(3, dim ~/ 20);
  final hi = math.max(3, dim ~/ 2);
  if (hi <= lo + 2) return (null, 0.0);
  final seg = acNorm.sublist(lo, math.min(hi, acNorm.length));
  final peaks = _findLocalMaxima(seg);
  if (peaks.isEmpty) return (null, 0.0);

  int tallest = peaks.first;
  double tallestVal = seg[tallest];
  for (final p in peaks) {
    if (seg[p] > tallestVal) {
      tallest = p;
      tallestVal = seg[p];
    }
  }

  // The tallest autocorrelation peak is occasionally a harmonic (2x, 3x the
  // true tile pitch) rather than the fundamental. Only override it with a
  // sub-divided candidate when that candidate is ALSO an independently
  // qualifying peak and nearly as strong as the tallest peak.
  int best = tallest;
  for (int divisor = 2; divisor < 7; divisor++) {
    final candidateTarget = tallest / divisor;
    if (candidateTarget < 1) break;
    final tol = math.max(1.0, 0.1 * candidateTarget);
    int? candidate;
    double candidateVal = -1;
    for (final p in peaks) {
      if ((p - candidateTarget).abs() <= tol && seg[p] > candidateVal) {
        candidate = p;
        candidateVal = seg[p];
      }
    }
    if (candidate != null && seg[candidate] >= 0.85 * tallestVal) {
      best = candidate;
    }
  }

  return (lo + best, acNorm[lo + best]);
}

/// Estimate tile pitch for one blob from the RAW (pre-morphology) mask
/// restricted to its bounding box. Returns (pitch_px, confidence, dim) —
/// dim is the blob's extent along the run axis, in the same (downscaled)
/// units as [maskRaw].
(int?, double, int) _blobPitch(Uint8List maskRaw, int maskW, int x, int y, int w, int h, bool vertical) {
  late final List<double> profile;
  late final int dim;
  if (vertical) {
    dim = h;
    profile = List<double>.filled(h, 0.0);
    for (int ry = 0; ry < h; ry++) {
      int sum = 0;
      final rowOff = (y + ry) * maskW;
      for (int rx = 0; rx < w; rx++) {
        sum += maskRaw[rowOff + x + rx];
      }
      profile[ry] = sum / w;
    }
  } else {
    dim = w;
    profile = List<double>.filled(w, 0.0);
    for (int rx = 0; rx < w; rx++) {
      int sum = 0;
      for (int ry = 0; ry < h; ry++) {
        sum += maskRaw[(y + ry) * maskW + x + rx];
      }
      profile[rx] = sum / h;
    }
  }
  final (pitch, confidence) = _estimatePitch(profile, dim);
  return (pitch, confidence, dim);
}

// ───────── Joint 13/14-tile-count resolution ─────────

const List<int> _handSizes = [13, 14];
const double _dropMinCost = 0.3;
const double _dropCostMultiplier = 2.0;
const double _maxTotalCost = 3.0;

Map<int, double> _pitchCountCosts(double dim, List<double> pitches) {
  final costs = <int, double>{};
  for (final p in pitches) {
    if (p <= 0) continue;
    final n0 = math.max(0, (dim / p).round());
    for (final n in [n0 - 1, n0, n0 + 1]) {
      if (n <= 0) continue;
      final cost = (dim - n * p).abs() / p;
      final existing = costs[n];
      if (existing == null || cost < existing) {
        costs[n] = cost;
      }
    }
  }
  return costs;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Resolve each kept blob's tile count using the fact that a mahjong hand
/// has exactly 13 or 14 tiles. See `_resolve_tile_counts` in
/// `app/tile_recognizer_local.py` for the full rationale.
List<int> _resolveTileCounts(List<double> dims, List<(int?, double, int)> blobPitches) {
  const referenceConfidence = 0.50;
  const minConfidence = 0.30;

  final ownPitches = [for (final bp in blobPitches) if (bp.$1 != null) bp.$1!.toDouble()];
  final confidentPitches = [
    for (final bp in blobPitches)
      if (bp.$1 != null && bp.$2 >= referenceConfidence) bp.$1!.toDouble(),
  ];
  final referencePitch = confidentPitches.isNotEmpty ? _median(confidentPitches) : null;
  final fallbackPitch = ownPitches.isNotEmpty ? _median(ownPitches) : null;

  final perBlobCosts = <Map<int, double>>[];
  for (int i = 0; i < dims.length; i++) {
    final pitch = blobPitches[i].$1;
    final hypotheses = <double>[
      ?referencePitch,
      if (pitch != null) pitch.toDouble(),
      ?fallbackPitch,
      if (pitch != null) pitch / 2,
      if (pitch != null) pitch / 3,
    ];
    final costs = _pitchCountCosts(dims[i], hypotheses);
    if (costs.isNotEmpty) {
      final minCost = costs.values.reduce(math.min);
      costs[0] = math.max(_dropMinCost, _dropCostMultiplier * minCost);
    }
    perBlobCosts.add(costs);
  }

  List<int>? bestCombo;
  double bestCost = double.infinity;
  final maxHand = _handSizes.reduce(math.max);

  void search(int i, List<int> chosen, int sum, double costSoFar) {
    if (costSoFar >= bestCost) return;
    if (i == perBlobCosts.length) {
      if (_handSizes.contains(sum)) {
        bestCombo = List<int>.from(chosen);
        bestCost = costSoFar;
      }
      return;
    }
    for (final entry in perBlobCosts[i].entries) {
      if (sum + entry.key > maxHand) continue;
      chosen.add(entry.key);
      search(i + 1, chosen, sum + entry.key, costSoFar + entry.value);
      chosen.removeLast();
    }
  }

  search(0, <int>[], 0, 0.0);

  if (bestCombo != null && bestCost <= _maxTotalCost) {
    return bestCombo!;
  }

  final resolved = <int>[];
  for (int i = 0; i < dims.length; i++) {
    final (pitch, confidence, _) = blobPitches[i];
    if (pitch != null && confidence >= referenceConfidence) {
      resolved.add(math.max(1, (dims[i] / pitch).round()));
    } else if (referencePitch != null) {
      resolved.add(math.max(1, (dims[i] / referencePitch).round()));
    } else if (pitch != null && confidence >= minConfidence) {
      resolved.add(math.max(1, (dims[i] / pitch).round()));
    } else {
      resolved.add(1);
    }
  }
  return resolved;
}
