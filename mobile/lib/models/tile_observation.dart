class TileCandidate {
  final String tile;
  final double confidence;

  const TileCandidate({required this.tile, required this.confidence});

  factory TileCandidate.fromJson(Map<String, dynamic> json) {
    return TileCandidate(
      tile: json['tile'] as String,
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'tile': tile, 'confidence': confidence};
}

class ObservationBoundingBox {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const ObservationBoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  factory ObservationBoundingBox.fromJson(Map<String, dynamic> json) {
    return ObservationBoundingBox(
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      right: (json['right'] as num).toDouble(),
      bottom: (json['bottom'] as num).toDouble(),
    );
  }

  bool isValidFor({required int imageWidth, required int imageHeight}) {
    return left >= 0 &&
        top >= 0 &&
        left < right &&
        top < bottom &&
        right <= imageWidth &&
        bottom <= imageHeight;
  }

  Map<String, dynamic> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };
}

class ObservationImage {
  static const orientedImagePixels = 'oriented_image_pixels';

  final int width;
  final int height;
  final String coordinateSpace;

  const ObservationImage({
    required this.width,
    required this.height,
    this.coordinateSpace = orientedImagePixels,
  });

  factory ObservationImage.fromJson(Map<String, dynamic> json) {
    return ObservationImage(
      width: json['width'] as int,
      height: json['height'] as int,
      coordinateSpace: json['coordinate_space'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    'coordinate_space': coordinateSpace,
  };
}

class TileObservation {
  final String observationId;
  final int index;
  final List<TileCandidate> candidates;
  final ObservationBoundingBox? bbox;
  final double? rotationDegrees;
  final String? visualGroupId;

  const TileObservation({
    required this.observationId,
    required this.index,
    required this.candidates,
    this.bbox,
    this.rotationDegrees,
    this.visualGroupId,
  });

  factory TileObservation.fromJson(Map<String, dynamic> json) {
    return TileObservation(
      observationId: json['observation_id'] as String,
      index: json['index'] as int,
      candidates: (json['candidates'] as List<dynamic>)
          .map(
            (candidate) =>
                TileCandidate.fromJson(candidate as Map<String, dynamic>),
          )
          .toList(growable: false),
      bbox: json['bbox'] == null
          ? null
          : ObservationBoundingBox.fromJson(
              json['bbox'] as Map<String, dynamic>,
            ),
      rotationDegrees: (json['rotation_degrees'] as num?)?.toDouble(),
      visualGroupId: json['visual_group_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'observation_id': observationId,
    'index': index,
    'candidates': candidates.map((candidate) => candidate.toJson()).toList(),
    'bbox': bbox?.toJson(),
    'rotation_degrees': rotationDegrees,
    'visual_group_id': visualGroupId,
  };
}

class ObservationV1 {
  static const supportedSchemaVersion = '1';

  final String schemaVersion;
  final ObservationImage image;
  final List<TileObservation> observations;

  const ObservationV1({
    this.schemaVersion = supportedSchemaVersion,
    required this.image,
    required this.observations,
  });

  factory ObservationV1.fromJson(Map<String, dynamic> json) {
    final version = json['schema_version'] as String;
    if (version != supportedSchemaVersion) {
      throw FormatException('Unsupported observation schema version: $version');
    }
    return ObservationV1(
      schemaVersion: version,
      image: ObservationImage.fromJson(json['image'] as Map<String, dynamic>),
      observations: (json['observations'] as List<dynamic>)
          .map(
            (observation) =>
                TileObservation.fromJson(observation as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'image': image.toJson(),
    'observations': observations
        .map((observation) => observation.toJson())
        .toList(),
  };
}
