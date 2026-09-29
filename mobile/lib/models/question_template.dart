class QuestionTemplate {
  const QuestionTemplate({
    required this.id,
    required this.name,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.accountUid,
    this.pendingSync = false,
    this.deleted = false,
  });

  final String id;
  final String name;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? accountUid;
  final bool pendingSync;
  final bool deleted;

  factory QuestionTemplate.fromJson(Map<String, dynamic> json) =>
      QuestionTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(
          (json['updated_at'] ?? json['created_at']) as String,
        ),
        accountUid: json['account_uid'] as String?,
        pendingSync: json['pending_sync'] as bool? ?? false,
        deleted: json['deleted'] as bool? ?? false,
      );

  Map<String, dynamic> toJson({bool includeLocalState = true}) => {
        'id': id,
        'name': name,
        'body': body,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        if (includeLocalState) 'account_uid': accountUid,
        if (includeLocalState) 'pending_sync': pendingSync,
        if (includeLocalState) 'deleted': deleted,
      };

  QuestionTemplate copyWith({
    String? name,
    String? body,
    DateTime? updatedAt,
    String? accountUid,
    bool? pendingSync,
    bool? deleted,
  }) =>
      QuestionTemplate(
        id: id,
        name: name ?? this.name,
        body: body ?? this.body,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        accountUid: accountUid ?? this.accountUid,
        pendingSync: pendingSync ?? this.pendingSync,
        deleted: deleted ?? this.deleted,
      );

  static String automaticName(String message) {
    final normalized = message.trim().replaceAll(RegExp(r'\s+'), ' ');
    return String.fromCharCodes(normalized.runes.take(30));
  }
}

class QuestionTemplateCollection {
  static const maxItems = 20;

  static List<QuestionTemplate> saveMessage({
    required List<QuestionTemplate> items,
    required String id,
    required String message,
    required DateTime now,
    String? accountUid,
  }) {
    final body = message.trim();
    if (body.isEmpty) throw ArgumentError('Message must not be empty');
    if (items.any((item) => !item.deleted && item.body == body)) return items;
    if (items.where((item) => !item.deleted).length >= maxItems) {
      throw StateError('Question template limit reached');
    }
    return [
      QuestionTemplate(
        id: id,
        name: QuestionTemplate.automaticName(body),
        body: body,
        createdAt: now,
        updatedAt: now,
        accountUid: accountUid,
        pendingSync: accountUid != null,
      ),
      ...items,
    ];
  }
}
