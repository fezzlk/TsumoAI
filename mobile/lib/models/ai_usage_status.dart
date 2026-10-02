class AIUsageStatus {
  const AIUsageStatus({
    required this.period,
    required this.plan,
    required this.includedLimit,
    required this.includedUsed,
    required this.bonusRemaining,
    required this.remaining,
    required this.resetsAt,
  });

  final String period;
  final String plan;
  final int includedLimit;
  final int includedUsed;
  final int bonusRemaining;
  final int remaining;
  final DateTime resetsAt;

  bool get exhausted => remaining <= 0;
  String get planLabel => plan == 'subscription' ? 'サブスクリプション' : '無料';

  factory AIUsageStatus.fromJson(Map<String, dynamic> json) => AIUsageStatus(
    period: json['period'] as String,
    plan: json['plan'] as String,
    includedLimit: (json['included_limit'] as num).toInt(),
    includedUsed: (json['included_used'] as num).toInt(),
    bonusRemaining: (json['bonus_remaining'] as num).toInt(),
    remaining: (json['remaining'] as num).toInt(),
    resetsAt: DateTime.parse(json['resets_at'] as String).toLocal(),
  );
}
