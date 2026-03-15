class Meld {
  final String type;
  final List<String> tiles;
  final bool open;

  Meld({required this.type, required this.tiles, required this.open});

  Map<String, dynamic> toJson() => {
        'type': type,
        'tiles': tiles,
        'open': open,
      };
}

class HandInput {
  final List<String> closedTiles;
  final List<Meld> melds;
  final String winTile;

  HandInput({
    required this.closedTiles,
    required this.melds,
    required this.winTile,
  });

  Map<String, dynamic> toJson() => {
        'closed_tiles': closedTiles,
        'melds': melds.map((m) => m.toJson()).toList(),
        'win_tile': winTile,
      };
}

class ContextInput {
  final String winType;
  final bool isDealer;
  final String roundWind;
  final String seatWind;
  final bool riichi;
  final bool doubleRiichi;
  final bool ippatsu;
  final bool haitei;
  final bool houtei;
  final bool rinshan;
  final bool chankan;
  final bool chiihou;
  final bool tenhou;
  final List<String> doraIndicators;
  final List<String> uraDoraIndicators;
  final int akaDora;
  final int honba;
  final int kyotaku;

  ContextInput({
    this.winType = 'tsumo',
    this.isDealer = false,
    this.roundWind = 'E',
    this.seatWind = 'S',
    this.riichi = false,
    this.doubleRiichi = false,
    this.ippatsu = false,
    this.haitei = false,
    this.houtei = false,
    this.rinshan = false,
    this.chankan = false,
    this.chiihou = false,
    this.tenhou = false,
    this.doraIndicators = const [],
    this.uraDoraIndicators = const [],
    this.akaDora = 0,
    this.honba = 0,
    this.kyotaku = 0,
  });

  Map<String, dynamic> toJson() => {
        'win_type': winType,
        'is_dealer': isDealer,
        'round_wind': roundWind,
        'seat_wind': seatWind,
        'riichi': riichi,
        'double_riichi': doubleRiichi,
        'ippatsu': ippatsu,
        'haitei': haitei,
        'houtei': houtei,
        'rinshan': rinshan,
        'chankan': chankan,
        'chiihou': chiihou,
        'tenhou': tenhou,
        'dora_indicators': doraIndicators,
        'ura_dora_indicators': uraDoraIndicators,
        'aka_dora_count': akaDora,
        'honba': honba,
        'kyotaku': kyotaku,
      };
}

class RuleSet {
  final bool akaAri;
  final bool kuitanAri;
  final bool doubleYakumanAri;
  final bool kazoeYakumanAri;
  final int renpuFu;

  RuleSet({
    this.akaAri = true,
    this.kuitanAri = true,
    this.doubleYakumanAri = true,
    this.kazoeYakumanAri = true,
    this.renpuFu = 4,
  });

  Map<String, dynamic> toJson() => {
        'aka_ari': akaAri,
        'kuitan_ari': kuitanAri,
        'double_yakuman_ari': doubleYakumanAri,
        'kazoe_yakuman_ari': kazoeYakumanAri,
        'renpu_fu': renpuFu,
      };
}

class ScoreRequest {
  final HandInput hand;
  final ContextInput context;
  final RuleSet rules;

  ScoreRequest({
    required this.hand,
    required this.context,
    required this.rules,
  });

  Map<String, dynamic> toJson() => {
        'hand': hand.toJson(),
        'context': context.toJson(),
        'rules': rules.toJson(),
      };
}
