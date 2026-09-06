enum FactStatus {
  confirmed('confirmed'),
  inferred('inferred'),
  unknown('unknown');

  const FactStatus(this.wireValue);
  final String wireValue;

  static FactStatus fromWireValue(String value) => values.firstWhere(
    (status) => status.wireValue == value,
    orElse: () => throw FormatException('Unsupported fact status: $value'),
  );
}

class MeldInterpretation {
  final List<String> observationIds;
  final String type;
  final List<String> tiles;
  final bool? open;
  final FactStatus status;
  final double confidence;
  final List<String> evidence;

  const MeldInterpretation({
    required this.observationIds,
    required this.type,
    required this.tiles,
    required this.open,
    required this.status,
    required this.confidence,
    required this.evidence,
  });

  factory MeldInterpretation.fromJson(Map<String, dynamic> json) {
    return MeldInterpretation(
      observationIds: (json['observation_ids'] as List<dynamic>).cast<String>(),
      type: json['type'] as String,
      tiles: (json['tiles'] as List<dynamic>).cast<String>(),
      open: json['open'] as bool?,
      status: FactStatus.fromWireValue(json['status'] as String),
      confidence: (json['confidence'] as num).toDouble(),
      evidence: (json['evidence'] as List<dynamic>? ?? const []).cast<String>(),
    );
  }
}

class WinningTileInterpretation {
  final String? observationId;
  final String? tile;
  final FactStatus status;
  final double confidence;
  final List<String> evidence;

  const WinningTileInterpretation({
    required this.observationId,
    required this.tile,
    required this.status,
    required this.confidence,
    required this.evidence,
  });

  factory WinningTileInterpretation.fromJson(Map<String, dynamic> json) {
    return WinningTileInterpretation(
      observationId: json['observation_id'] as String?,
      tile: json['tile'] as String?,
      status: FactStatus.fromWireValue(json['status'] as String),
      confidence: (json['confidence'] as num).toDouble(),
      evidence: (json['evidence'] as List<dynamic>? ?? const []).cast<String>(),
    );
  }
}

class InterpretationResult {
  final List<MeldInterpretation> melds;
  final WinningTileInterpretation winningTile;
  final bool requiresUserConfirmation;
  final List<String> warnings;

  const InterpretationResult({
    required this.melds,
    required this.winningTile,
    required this.requiresUserConfirmation,
    required this.warnings,
  });

  factory InterpretationResult.fromJson(Map<String, dynamic> json) {
    return InterpretationResult(
      melds: (json['melds'] as List<dynamic>? ?? const [])
          .map(
            (meld) => MeldInterpretation.fromJson(meld as Map<String, dynamic>),
          )
          .toList(growable: false),
      winningTile: WinningTileInterpretation.fromJson(
        json['winning_tile'] as Map<String, dynamic>,
      ),
      requiresUserConfirmation: json['requires_user_confirmation'] as bool,
      warnings: (json['warnings'] as List<dynamic>? ?? const []).cast<String>(),
    );
  }
}
