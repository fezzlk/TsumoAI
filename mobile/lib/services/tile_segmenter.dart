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
  // to the original image's pixel coordinate space. Each slot's cross-axis
  // position/extent tracks the blob's local centerline (see
  // `_blobCenterline`) rather than the blob's own fixed bbox, so a curved
  // (non-straight) tile row doesn't drift slots away from the true tiles.
  final result = <Rect>[];
  for (int i = 0; i < kept.length; i++) {
    final n = tileCounts[i];
    if (n <= 0) continue;
    final c = kept[i];
    final centerline = _blobCenterline(mask, mW, c.x, c.y, c.w, c.h, vertical);
    final halfExtent = centerline.extent / 2;
    if (vertical) {
      final subH = c.h / n;
      for (int j = 0; j < n; j++) {
        final sy = c.y + (j * subH).toInt();
        final ey = c.y + ((j + 1) * subH).toInt();
        final rel0 = sy - c.y;
        final rel1 = math.min(centerline.centers.length, math.max(rel0 + 1, ey - c.y));
        final sliceCenter = _median(centerline.centers.sublist(rel0, rel1));
        var sx = (sliceCenter - halfExtent).round();
        var ex = sx + centerline.extent.round();
        sx = sx.clamp(0, mW);
        ex = ex.clamp(sx, mW);
        result.add(Rect.fromLTWH(
          (sx * scale).toDouble(),
          (sy * scale).toDouble(),
          ((ex - sx) * scale).toDouble(),
          ((ey - sy) * scale).toDouble(),
        ));
      }
    } else {
      final subW = c.w / n;
      for (int j = 0; j < n; j++) {
        final sx = c.x + (j * subW).toInt();
        final ex = c.x + ((j + 1) * subW).toInt();
        final rel0 = sx - c.x;
        final rel1 = math.min(centerline.centers.length, math.max(rel0 + 1, ex - c.x));
        final sliceCenter = _median(centerline.centers.sublist(rel0, rel1));
        var sy = (sliceCenter - halfExtent).round();
        var ey = sy + centerline.extent.round();
        sy = sy.clamp(0, mH);
        ey = ey.clamp(sy, mH);
        result.add(Rect.fromLTWH(
          (sx * scale).toDouble(),
          (sy * scale).toDouble(),
          ((ex - sx) * scale).toDouble(),
          ((ey - sy) * scale).toDouble(),
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
  // A no-op if the caller already baked orientation in (bakeOrientation
  // clears the tag once applied); kept here defensively so this function is
  // correct standalone, e.g. if called directly on a fresh capture.
  final oriented = img.bakeOrientation(decoded);
  final rgb = oriented.numChannels == 3 ? oriented : oriented.convert(numChannels: 3);
  return segmentTiles(rgb);
}

/// Given a rough (axis-aligned) detected bounding box for one tile, produce
/// a straightened, tightly-cropped image suitable for classification —
/// correcting that individual tile's own tilt and trimming background/
/// neighboring-tile bleed that a naive equal-subdivision crop includes.
/// This is a small, local, per-tile refinement; it does not touch (and
/// cannot destabilize) the whole-row detection/counting in [segmentTiles].
/// Falls back to a plain crop of [roughBox] if no clear tile blob is found.
img.Image refineTileCrop(img.Image source, Rect roughBox) {
  final srcW = source.width, srcH = source.height;
  final fallback = _plainCrop(source, roughBox);

  final marginX = roughBox.width * 0.20;
  final marginY = roughBox.height * 0.20;
  final px0 = (roughBox.left - marginX).round().clamp(0, srcW - 1);
  final py0 = (roughBox.top - marginY).round().clamp(0, srcH - 1);
  final px1 = (roughBox.right + marginX).round().clamp(px0 + 1, srcW);
  final py1 = (roughBox.bottom + marginY).round().clamp(py0 + 1, srcH);
  final padded = img.copyCrop(source, x: px0, y: py0, width: px1 - px0, height: py1 - py0);

  final blob = _pickCentralBlob(_findLocalBlobs(padded), padded.width, padded.height);
  if (blob == null) return fallback;

  // Touching tiles can share a seam too faint to separate even in this
  // small local (non-morphed) mask — the same low-contrast, white-on-white
  // problem that motivated the periodicity-based approach in [segmentTiles]
  // rather than seam/edge detection. If the "central" blob is much larger
  // than the rough box already resolved for this tile, it has likely
  // absorbed a neighbor; rather than straighten+trim that (which would
  // actively make the crop worse), fall back to the safe naive crop.
  final expectedArea = roughBox.width * roughBox.height;
  if (expectedArea > 0 && _bboxArea(blob) > expectedArea * 1.6) {
    return fallback;
  }

  final angle = _bestStraighteningAngleDegrees(blob.points);
  if (angle.abs() < 0.05) {
    return _tightCropToBlob(padded, blob) ?? fallback;
  }

  // The point-cloud search above gives the correction *magnitude* but not
  // reliably its sign relative to copyRotate's rotation direction, and it
  // can also be a false positive on an already-straight tile (a small
  // spurious angle from mask noise). Resolve both by comparing three real
  // candidates — no rotation, +angle, -angle — and keeping whichever
  // actually yields the tightest (smallest-area) axis-aligned blob after
  // rotating the real image, rather than trusting the estimate blindly.
  // Cheap: the crop here is small, so this is only two extra rotations.
  final rotatedPos = img.copyRotate(padded, angle: angle, interpolation: img.Interpolation.linear);
  final rotatedNeg = img.copyRotate(padded, angle: -angle, interpolation: img.Interpolation.linear);
  final blobPos = _pickCentralBlob(_findLocalBlobs(rotatedPos), rotatedPos.width, rotatedPos.height);
  final blobNeg = _pickCentralBlob(_findLocalBlobs(rotatedNeg), rotatedNeg.width, rotatedNeg.height);

  final areaOriginal = _bboxArea(blob);
  final areaPos = blobPos == null ? double.infinity : _bboxArea(blobPos);
  final areaNeg = blobNeg == null ? double.infinity : _bboxArea(blobNeg);

  // A rotated candidate's bounding box can come out only marginally
  // smaller than the unrotated original by noise alone (mask-detection
  // jitter, interpolation), while actually looking worse (softened edges,
  // a slightly different blob picked up). Require a clear improvement —
  // not just "smaller" — before trusting a rotation over no rotation at
  // all; otherwise keep the original framing.
  const minImprovement = 0.90; // rotated area must be <= 90% of original
  final bestRotatedArea = math.min(areaPos, areaNeg);

  img.Image useImage;
  _LocalBlob useBlob;
  if (bestRotatedArea > areaOriginal * minImprovement) {
    useImage = padded;
    useBlob = blob;
  } else if (areaPos <= areaNeg) {
    useImage = rotatedPos;
    useBlob = blobPos!;
  } else {
    useImage = rotatedNeg;
    useBlob = blobNeg!;
  }

  if (expectedArea > 0 && _bboxArea(useBlob) > expectedArea * 1.6) {
    return fallback;
  }
  return _tightCropToBlob(useImage, useBlob) ?? fallback;
}

img.Image _plainCrop(img.Image source, Rect box) {
  final x = box.left.round().clamp(0, source.width - 1);
  final y = box.top.round().clamp(0, source.height - 1);
  final w = box.width.round().clamp(1, source.width - x);
  final h = box.height.round().clamp(1, source.height - y);
  return img.copyCrop(source, x: x, y: y, width: w, height: h);
}

int _bboxArea(_LocalBlob b) => (b.maxX - b.minX + 1) * (b.maxY - b.minY + 1);

img.Image? _tightCropToBlob(img.Image image, _LocalBlob blob) {
  const pad = 3;
  final x = (blob.minX - pad).clamp(0, image.width - 1);
  final y = (blob.minY - pad).clamp(0, image.height - 1);
  final x1 = (blob.maxX + pad + 1).clamp(x + 1, image.width);
  final y1 = (blob.maxY + pad + 1).clamp(y + 1, image.height);
  return img.copyCrop(image, x: x, y: y, width: x1 - x, height: y1 - y);
}

/// A connected white-pixel blob found in a small local crop (full
/// resolution, no morphological cleanup — unlike [segmentTiles]'s global
/// mask, we want the seam to a touching neighbor tile to stay visible here
/// so it can be excluded).
class _LocalBlob {
  final int minX, minY, maxX, maxY, area;
  final List<(int, int)> points;
  _LocalBlob(this.minX, this.minY, this.maxX, this.maxY, this.area, this.points);
}

List<_LocalBlob> _findLocalBlobs(img.Image local) {
  final w = local.width, h = local.height;
  final mask = Uint8List(w * h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (_isWhitePixel(local, x, y)) mask[y * w + x] = 1;
    }
  }

  final labels = Int32List(w * h);
  int nextLabel = 0;
  final blobs = <_LocalBlob>[];

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final idx = y * w + x;
      if (mask[idx] == 0 || labels[idx] != 0) continue;

      nextLabel++;
      int minX = x, maxX = x, minY = y, maxY = y;
      final points = <(int, int)>[];
      final stack = <int>[idx];
      labels[idx] = nextLabel;

      while (stack.isNotEmpty) {
        final ci = stack.removeLast();
        final cx = ci % w, cy = ci ~/ w;
        points.add((cx, cy));
        if (cx < minX) minX = cx;
        if (cx > maxX) maxX = cx;
        if (cy < minY) minY = cy;
        if (cy > maxY) maxY = cy;

        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = cx + dx, ny = cy + dy;
            if (nx >= 0 && nx < w && ny >= 0 && ny < h) {
              final ni = ny * w + nx;
              if (mask[ni] != 0 && labels[ni] == 0) {
                labels[ni] = nextLabel;
                stack.add(ni);
              }
            }
          }
        }
      }

      blobs.add(_LocalBlob(minX, minY, maxX, maxY, points.length, points));
    }
  }
  return blobs;
}

_LocalBlob? _pickCentralBlob(List<_LocalBlob> blobs, int w, int h) {
  final minArea = math.max(20, 0.03 * w * h);
  final cx = w / 2.0, cy = h / 2.0;
  _LocalBlob? best;
  double bestDist = double.infinity;
  for (final b in blobs) {
    if (b.area < minArea) continue;
    final bboxArea = _bboxArea(b);
    if (bboxArea == 0 || b.area / bboxArea < 0.20) continue;
    final bcx = (b.minX + b.maxX) / 2.0;
    final bcy = (b.minY + b.maxY) / 2.0;
    final dist = (bcx - cx) * (bcx - cx) + (bcy - cy) * (bcy - cy);
    if (dist < bestDist) {
      bestDist = dist;
      best = b;
    }
  }
  return best;
}

/// Search for the rotation angle (degrees) that minimizes the axis-aligned
/// bounding-box area of [points] — an approximate minimum-area-rectangle
/// search by brute-force angle sweep (cheap for the small point sets
/// involved here; avoids implementing a full convex-hull/rotating-calipers
/// or PCA/eigendecomposition routine).
double _bestStraighteningAngleDegrees(List<(int, int)> points) {
  if (points.isEmpty) return 0.0;
  double sumX = 0, sumY = 0;
  for (final p in points) {
    sumX += p.$1;
    sumY += p.$2;
  }
  final cx = sumX / points.length, cy = sumY / points.length;

  double bestAngle = 0.0;
  double bestArea = double.infinity;

  double areaAt(double deg) {
    final rad = deg * math.pi / 180.0;
    final cosA = math.cos(rad), sinA = math.sin(rad);
    double minRx = double.infinity, maxRx = -double.infinity;
    double minRy = double.infinity, maxRy = -double.infinity;
    for (final p in points) {
      final dx = p.$1 - cx, dy = p.$2 - cy;
      final rx = dx * cosA - dy * sinA;
      final ry = dx * sinA + dy * cosA;
      if (rx < minRx) minRx = rx;
      if (rx > maxRx) maxRx = rx;
      if (ry < minRy) minRy = ry;
      if (ry > maxRy) maxRy = ry;
    }
    return (maxRx - minRx) * (maxRy - minRy);
  }

  for (double deg = -25; deg <= 25; deg += 2) {
    final area = areaAt(deg);
    if (area < bestArea) {
      bestArea = area;
      bestAngle = deg;
    }
  }
  final coarseBest = bestAngle;
  for (double deg = coarseBest - 2; deg <= coarseBest + 2; deg += 0.25) {
    final area = areaAt(deg);
    if (area < bestArea) {
      bestArea = area;
      bestAngle = deg;
    }
  }
  return bestAngle;
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

typedef _Centerline = ({List<double> centers, double extent});

const double _centerlineRowCoverageThreshold = 0.15;
const int _centerlineSmoothWindow = 5;

/// Compute a local cross-axis "centerline" and a single typical per-slice
/// extent for one blob, from the CLEANED (post-morphology) [mask] — kept
/// consistent with the same shape that determined the blob's bbox and
/// connectivity in the first place (unlike [_blobPitch], which deliberately
/// reads the raw pre-morphology mask to see the thin seams between
/// touching tiles).
///
/// For a [vertical] blob, `centers[ry]` (relative to the blob's own bbox)
/// is the cross-axis (x) center of the mask pixels in row `ry`, gap-filled
/// across rows with too little coverage to trust (the seam between tiles,
/// or a thin cross-section at a sharp bend) and smoothed with a moving
/// median to suppress single-row noise while preserving genuine curvature.
/// `extent` is one typical width for the whole blob — the median row width
/// across confidently-covered rows only — so a sharply-bent minority of
/// rows doesn't inflate every slice's width the way the blob's raw bbox
/// width does today (see [segmentTiles] doc on curved rows). Horizontal
/// blobs mirror this with rows/columns and x/y swapped.
///
/// Falls back to a single centered value spanning [w]/[h] when no row (or
/// column) anywhere in the blob has enough coverage to be trusted.
_Centerline _blobCenterline(
    Uint8List mask, int maskW, int x, int y, int w, int h, bool vertical) {
  final crossDim = vertical ? w : h;
  final runDim = vertical ? h : w;
  final centers = List<double>.filled(runDim, double.nan);
  final widths = <double>[];

  for (int r = 0; r < runDim; r++) {
    final xs = <int>[];
    for (int c = 0; c < crossDim; c++) {
      final mx = vertical ? x + c : x + r;
      final my = vertical ? y + r : y + c;
      if (mask[my * maskW + mx] != 0) xs.add(c);
    }
    if (xs.length >= _centerlineRowCoverageThreshold * crossDim) {
      final localCenter = _median([for (final v in xs) v.toDouble()]);
      centers[r] = (vertical ? x : y) + localCenter;
      widths.add((xs.last - xs.first + 1).toDouble());
    }
  }

  final extent = widths.isNotEmpty ? _median(widths) : crossDim.toDouble();

  final validIdx = [for (int r = 0; r < runDim; r++) if (!centers[r].isNaN) r];
  if (validIdx.isEmpty) {
    // No signal anywhere in this blob; fall back to a single centered value
    // for every slot, equivalent to today's fixed-position behavior.
    final fallbackCenter = (vertical ? x : y) + crossDim / 2;
    return (centers: List<double>.filled(runDim, fallbackCenter), extent: extent);
  }
  for (int r = 0; r < validIdx.first; r++) {
    centers[r] = centers[validIdx.first];
  }
  for (int r = validIdx.last + 1; r < runDim; r++) {
    centers[r] = centers[validIdx.last];
  }
  for (int k = 0; k < validIdx.length - 1; k++) {
    final r0 = validIdx[k], r1 = validIdx[k + 1];
    if (r1 - r0 <= 1) continue;
    final v0 = centers[r0], v1 = centers[r1];
    for (int r = r0 + 1; r < r1; r++) {
      centers[r] = v0 + (v1 - v0) * (r - r0) / (r1 - r0);
    }
  }

  final smoothed = List<double>.filled(runDim, 0.0);
  final half = _centerlineSmoothWindow ~/ 2;
  for (int r = 0; r < runDim; r++) {
    final lo = math.max(0, r - half);
    final hi = math.min(runDim - 1, r + half);
    smoothed[r] = _median(centers.sublist(lo, hi + 1));
  }

  return (centers: smoothed, extent: extent);
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
