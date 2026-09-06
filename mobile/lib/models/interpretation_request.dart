import 'tile_observation.dart';

enum HandOperation {
  score('score'),
  tenpai('tenpai'),
  discardAnalysis('discard_analysis');

  const HandOperation(this.wireValue);
  final String wireValue;

  static HandOperation fromWireValue(String value) => values.firstWhere(
    (operation) => operation.wireValue == value,
    orElse: () => throw FormatException('Unsupported operation: $value'),
  );
}

class ConfirmedTile {
  final String observationId;
  final String tile;

  const ConfirmedTile({required this.observationId, required this.tile});

  factory ConfirmedTile.fromJson(Map<String, dynamic> json) => ConfirmedTile(
    observationId: json['observation_id'] as String,
    tile: json['tile'] as String,
  );

  Map<String, dynamic> toJson() => {
    'observation_id': observationId,
    'tile': tile,
  };
}

class ConfirmedMeld {
  final List<String> observationIds;
  final String type;
  final bool open;

  const ConfirmedMeld({
    required this.observationIds,
    required this.type,
    required this.open,
  });

  factory ConfirmedMeld.fromJson(Map<String, dynamic> json) => ConfirmedMeld(
    observationIds: (json['observation_ids'] as List<dynamic>).cast<String>(),
    type: json['type'] as String,
    open: json['open'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'observation_ids': observationIds,
    'type': type,
    'open': open,
  };
}

class ConfirmationV1 {
  static const supportedSchemaVersion = '1';

  final String schemaVersion;
  final HandOperation operation;
  final List<ConfirmedTile> confirmedTiles;
  final String? confirmedWinningTileId;
  final List<ConfirmedMeld> confirmedMelds;

  const ConfirmationV1({
    this.schemaVersion = supportedSchemaVersion,
    required this.operation,
    required this.confirmedTiles,
    this.confirmedWinningTileId,
    this.confirmedMelds = const [],
  });

  factory ConfirmationV1.fromJson(Map<String, dynamic> json) {
    final version = json['schema_version'] as String;
    if (version != supportedSchemaVersion) {
      throw FormatException(
        'Unsupported confirmation schema version: $version',
      );
    }
    return ConfirmationV1(
      schemaVersion: version,
      operation: HandOperation.fromWireValue(json['operation'] as String),
      confirmedTiles: (json['confirmed_tiles'] as List<dynamic>)
          .map((tile) => ConfirmedTile.fromJson(tile as Map<String, dynamic>))
          .toList(growable: false),
      confirmedWinningTileId: json['confirmed_winning_tile_id'] as String?,
      confirmedMelds: (json['confirmed_melds'] as List<dynamic>? ?? const [])
          .map((meld) => ConfirmedMeld.fromJson(meld as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'operation': operation.wireValue,
    'confirmed_tiles': confirmedTiles.map((tile) => tile.toJson()).toList(),
    'confirmed_winning_tile_id': confirmedWinningTileId,
    'confirmed_melds': confirmedMelds.map((meld) => meld.toJson()).toList(),
  };
}

/// Wire request for the interpretation endpoint during the V1 migration.
///
/// Observation and optional confirmation fields are flattened because the
/// current endpoint already accepts `observations` and confirmed facts at the
/// top level. Unknown V1 fields remain explicit for the backend migration.
class InterpretationRequest {
  final ObservationV1 observation;
  final ConfirmationV1? confirmation;

  const InterpretationRequest({required this.observation, this.confirmation});

  Map<String, dynamic> toJson() {
    final confirmationJson = confirmation?.toJson();
    return {
      ...observation.toJson(),
      if (confirmationJson != null) ...{
        'operation': confirmationJson['operation'],
        'confirmed_tiles': confirmationJson['confirmed_tiles'],
        'confirmed_winning_tile_id':
            confirmationJson['confirmed_winning_tile_id'],
        'confirmed_melds': confirmationJson['confirmed_melds'],
      },
    };
  }
}
