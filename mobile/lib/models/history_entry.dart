class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.purpose,
    required this.title,
    required this.summary,
    required this.details,
    this.roundLabel,
    this.accountUid,
  });

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String purpose;
  final String title;
  final String summary;
  final String? roundLabel;
  final Map<String, dynamic> details;
  final String? accountUid;

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(
      (json['updated_at'] ?? json['created_at']) as String,
    ),
    purpose: json['purpose'] as String,
    title: json['title'] as String,
    summary: json['summary'] as String,
    roundLabel: json['round_label'] as String?,
    accountUid: json['account_uid'] as String?,
    details: Map<String, dynamic>.from(json['details'] as Map? ?? const {}),
  );

  Map<String, dynamic> toJson({bool includeId = true}) => {
    if (includeId) 'id': id,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'purpose': purpose,
    'title': title,
    'summary': summary,
    'round_label': roundLabel,
    if (includeId) 'account_uid': accountUid,
    'details': details,
  };

  HistoryEntry copyWith({String? accountUid}) => HistoryEntry(
    id: id,
    createdAt: createdAt,
    updatedAt: updatedAt,
    purpose: purpose,
    title: title,
    summary: summary,
    roundLabel: roundLabel,
    details: details,
    accountUid: accountUid ?? this.accountUid,
  );
}
