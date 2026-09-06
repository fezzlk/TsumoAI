import '../models/tile_observation.dart';
import '../models/tile_quad.dart';

class ScanObservationInput {
  final int index;
  final List<TileCandidate> candidates;
  final TileQuad? quad;
  final String? observationId;
  final String? visualGroupId;

  const ScanObservationInput({
    required this.index,
    required this.candidates,
    this.quad,
    this.observationId,
    this.visualGroupId,
  });
}

ObservationV1 buildScanObservationV1({
  required int imageWidth,
  required int imageHeight,
  required List<ScanObservationInput> tiles,
}) {
  if (imageWidth <= 0 || imageHeight <= 0) {
    throw ArgumentError('Image dimensions must be positive');
  }

  final ids = <String>{};
  final indices = <int>{};
  final observations = tiles
      .map((tile) {
        final id =
            tile.observationId ??
            'tile-${tile.index.toString().padLeft(3, '0')}';
        if (id.isEmpty || !ids.add(id)) {
          throw ArgumentError(
            'Observation IDs must be non-empty and unique: $id',
          );
        }
        if (tile.index < 0 || !indices.add(tile.index)) {
          throw ArgumentError(
            'Observation indices must be non-negative and unique',
          );
        }

        final bbox = tile.quad?.observationBoundingBox;
        if (bbox != null &&
            !bbox.isValidFor(
              imageWidth: imageWidth,
              imageHeight: imageHeight,
            )) {
          throw ArgumentError('Tile $id has a bounding box outside the image');
        }
        for (final candidate in tile.candidates) {
          if (!candidate.confidence.isFinite ||
              candidate.confidence < 0 ||
              candidate.confidence > 1) {
            throw ArgumentError('Tile $id has invalid candidate confidence');
          }
        }

        final candidates = [...tile.candidates]
          ..sort((left, right) => right.confidence.compareTo(left.confidence));
        return TileObservation(
          observationId: id,
          index: tile.index,
          candidates: candidates,
          bbox: bbox,
          rotationDegrees: tile.quad?.orientationDegrees,
          visualGroupId: tile.visualGroupId,
        );
      })
      .toList(growable: false);

  return ObservationV1(
    image: ObservationImage(width: imageWidth, height: imageHeight),
    observations: observations,
  );
}
