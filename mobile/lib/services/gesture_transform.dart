import 'package:flutter/material.dart';

/// Composes a new display transform for a drag/pinch/rotate gesture in
/// progress on an image.
///
/// Flutter's scale gesture recognizer reports relative to gesture start (as
/// in [ScaleUpdateDetails.scale]/[.rotation]), not per-frame deltas. The
/// whole current gesture's transform is rebuilt from [startTransform] on
/// every call, pivoting scale and rotation around [startFocalLocal] — the
/// point that was under the fingers when the gesture began — so that point
/// stays under [currentFocalLocal] regardless of any rotation already
/// applied before the gesture started. Coordinates are all in the same
/// "local" space (i.e. relative to the transformed widget's own origin).
///
/// Shared between `scan_screen.dart` (14-tile capture) and
/// `training_data_screen.dart` (single-tile capture) — both screens let the
/// user pan/zoom/rotate a captured photo to align it against a fixed
/// on-screen slot overlay, and both need this same pivot-correct
/// composition (a naive per-axis add of offset/scale/rotation instead of a
/// single composed matrix was tried first and had two bugs: pinch-zoom
/// always pivoted on the image center ignoring the pinch point, and
/// dragging after rotating looked reversed).
Matrix4 composeGestureTransform({
  required Matrix4 startTransform,
  required Offset startFocalLocal,
  required double startScale,
  required Offset currentFocalLocal,
  required double scaleFactorSinceStart,
  required double rotationSinceStart,
  double minScale = 0.5,
  double maxScale = 5.0,
}) {
  final targetScale = (startScale * scaleFactorSinceStart).clamp(
    minScale,
    maxScale,
  );
  final relativeScale = targetScale / startScale;
  final delta = Matrix4.identity()
    ..translateByDouble(currentFocalLocal.dx, currentFocalLocal.dy, 0, 1)
    ..rotateZ(rotationSinceStart)
    ..scaleByDouble(relativeScale, relativeScale, relativeScale, 1)
    ..translateByDouble(-startFocalLocal.dx, -startFocalLocal.dy, 0, 1);
  return delta.multiplied(startTransform);
}
