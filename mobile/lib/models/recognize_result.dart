import 'tile_observation.dart';

export 'tile_observation.dart' show ObservationBoundingBox, TileCandidate;

class HandSlot {
  final int index;
  final String top;
  final List<TileCandidate> candidates;
  final bool ambiguous;
  final String? observationId;
  final ObservationBoundingBox? bbox;
  final double? rotationDegrees;
  final String? visualGroupId;

  HandSlot({
    required this.index,
    required this.top,
    required this.candidates,
    required this.ambiguous,
    this.observationId,
    this.bbox,
    this.rotationDegrees,
    this.visualGroupId,
  });

  factory HandSlot.fromJson(Map<String, dynamic> json) {
    return HandSlot(
      index: json['index'] as int,
      top: json['top'] as String,
      candidates:
          (json['candidates'] as List?)
              ?.map((c) => TileCandidate.fromJson(c))
              .toList() ??
          [],
      ambiguous: json['ambiguous'] as bool,
      observationId: json['observation_id'] as String?,
      bbox: json['bbox'] == null
          ? null
          : ObservationBoundingBox.fromJson(
              json['bbox'] as Map<String, dynamic>,
            ),
      rotationDegrees: (json['rotation_degrees'] as num?)?.toDouble(),
      visualGroupId: json['visual_group_id'] as String?,
    );
  }
}

class HandEstimate {
  final int tilesCount;
  final List<HandSlot> slots;

  HandEstimate({required this.tilesCount, required this.slots});

  factory HandEstimate.fromJson(Map<String, dynamic> json) {
    return HandEstimate(
      tilesCount: json['tiles_count'] as int,
      slots: (json['slots'] as List).map((s) => HandSlot.fromJson(s)).toList(),
    );
  }

  List<String> get topTiles => slots.map((s) => s.top).toList();
}

class RecognizeResponse {
  final String recognitionId;
  final HandEstimate handEstimate;
  final List<String> warnings;

  /// Raw JSON from the API response (used for feedback submission).
  final Map<String, dynamic> rawJson;

  RecognizeResponse({
    required this.recognitionId,
    required this.handEstimate,
    required this.warnings,
    required this.rawJson,
  });

  factory RecognizeResponse.fromJson(Map<String, dynamic> json) {
    return RecognizeResponse(
      recognitionId: json['recognition_id'] as String,
      handEstimate: HandEstimate.fromJson(json['hand_estimate']),
      warnings: (json['warnings'] as List?)?.cast<String>() ?? [],
      rawJson: json,
    );
  }
}

class RecognizeJobStatus {
  final String jobId;
  final String status;
  final RecognizeResponse? result;
  final String? error;

  RecognizeJobStatus({
    required this.jobId,
    required this.status,
    this.result,
    this.error,
  });

  factory RecognizeJobStatus.fromJson(Map<String, dynamic> json) {
    return RecognizeJobStatus(
      jobId: json['job_id'] as String,
      status: json['status'] as String,
      result: json['result'] != null
          ? RecognizeResponse.fromJson(json['result'])
          : null,
      error: json['error'] as String?,
    );
  }
}
