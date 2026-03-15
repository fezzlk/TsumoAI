class YakuItem {
  final String name;
  final int han;

  YakuItem({required this.name, required this.han});

  factory YakuItem.fromJson(Map<String, dynamic> json) {
    return YakuItem(
      name: json['name'] as String,
      han: json['han'] as int,
    );
  }
}

class DoraBreakdown {
  final int dora;
  final int akaDora;
  final int uraDora;

  DoraBreakdown({
    required this.dora,
    required this.akaDora,
    required this.uraDora,
  });

  factory DoraBreakdown.fromJson(Map<String, dynamic> json) {
    return DoraBreakdown(
      dora: json['dora'] as int,
      akaDora: json['aka_dora'] as int,
      uraDora: json['ura_dora'] as int,
    );
  }
}

class FuBreakdownItem {
  final String name;
  final int fu;

  FuBreakdownItem({required this.name, required this.fu});

  factory FuBreakdownItem.fromJson(Map<String, dynamic> json) {
    return FuBreakdownItem(
      name: json['name'] as String,
      fu: json['fu'] as int,
    );
  }
}

class Points {
  final int ron;
  final int tsumoDealerPay;
  final int tsumoNonDealerPay;

  Points({
    required this.ron,
    required this.tsumoDealerPay,
    required this.tsumoNonDealerPay,
  });

  factory Points.fromJson(Map<String, dynamic> json) {
    return Points(
      ron: json['ron'] as int? ?? 0,
      tsumoDealerPay: json['tsumo_dealer_pay'] as int? ?? 0,
      tsumoNonDealerPay: json['tsumo_non_dealer_pay'] as int? ?? 0,
    );
  }
}

class Payments {
  final int handPointsReceived;
  final int handPointsWithHonba;
  final int honbaBonus;
  final int kyotakuBonus;
  final int totalReceived;

  Payments({
    required this.handPointsReceived,
    required this.handPointsWithHonba,
    required this.honbaBonus,
    required this.kyotakuBonus,
    required this.totalReceived,
  });

  factory Payments.fromJson(Map<String, dynamic> json) {
    return Payments(
      handPointsReceived: json['hand_points_received'] as int,
      handPointsWithHonba: json['hand_points_with_honba'] as int,
      honbaBonus: json['honba_bonus'] as int? ?? 0,
      kyotakuBonus: json['kyotaku_bonus'] as int? ?? 0,
      totalReceived: json['total_received'] as int,
    );
  }
}

class ScoreResult {
  final int han;
  final int fu;
  final List<FuBreakdownItem> fuBreakdown;
  final List<YakuItem> yaku;
  final List<String> yakuman;
  final DoraBreakdown dora;
  final String pointLabel;
  final Points points;
  final Payments payments;
  final List<String> explanation;

  ScoreResult({
    required this.han,
    required this.fu,
    required this.fuBreakdown,
    required this.yaku,
    required this.yakuman,
    required this.dora,
    required this.pointLabel,
    required this.points,
    required this.payments,
    required this.explanation,
  });

  factory ScoreResult.fromJson(Map<String, dynamic> json) {
    return ScoreResult(
      han: json['han'] as int,
      fu: json['fu'] as int,
      fuBreakdown: (json['fu_breakdown'] as List?)
              ?.map((e) => FuBreakdownItem.fromJson(e))
              .toList() ??
          [],
      yaku: (json['yaku'] as List?)
              ?.map((e) => YakuItem.fromJson(e))
              .toList() ??
          [],
      yakuman: (json['yakuman'] as List?)?.cast<String>() ?? [],
      dora: DoraBreakdown.fromJson(json['dora']),
      pointLabel: json['point_label'] as String,
      points: Points.fromJson(json['points']),
      payments: Payments.fromJson(json['payments']),
      explanation: (json['explanation'] as List?)?.cast<String>() ?? [],
    );
  }
}

class ScoreResponse {
  final String scoreId;
  final String status;
  final ScoreResult result;
  final List<String> warnings;

  ScoreResponse({
    required this.scoreId,
    required this.status,
    required this.result,
    required this.warnings,
  });

  factory ScoreResponse.fromJson(Map<String, dynamic> json) {
    return ScoreResponse(
      scoreId: json['score_id'] as String,
      status: json['status'] as String,
      result: ScoreResult.fromJson(json['result']),
      warnings: (json['warnings'] as List?)?.cast<String>() ?? [],
    );
  }
}
