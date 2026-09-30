class OfficialAIChatTemplate {
  const OfficialAIChatTemplate({
    required this.id,
    required this.kind,
    required this.purpose,
    required this.label,
    required this.body,
    required this.enabled,
    required this.sortOrder,
  });

  final String id;
  final String kind;
  final String purpose;
  final String label;
  final String body;
  final bool enabled;
  final int sortOrder;

  factory OfficialAIChatTemplate.fromJson(Map<String, dynamic> json) =>
      OfficialAIChatTemplate(
        id: json['id'] as String,
        kind: json['kind'] as String,
        purpose: json['purpose'] as String? ?? 'all',
        label: json['label'] as String,
        body: json['body'] as String,
        enabled: json['enabled'] as bool? ?? true,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'purpose': purpose,
    'label': label,
    'body': body,
    'enabled': enabled,
    'sort_order': sortOrder,
  };

  OfficialAIChatTemplate copyWith({
    String? id,
    String? kind,
    String? purpose,
    String? label,
    String? body,
    bool? enabled,
    int? sortOrder,
  }) => OfficialAIChatTemplate(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    purpose: purpose ?? this.purpose,
    label: label ?? this.label,
    body: body ?? this.body,
    enabled: enabled ?? this.enabled,
    sortOrder: sortOrder ?? this.sortOrder,
  );
}

class OfficialAIChatTemplateConfig {
  const OfficialAIChatTemplateConfig({
    required this.version,
    required this.items,
    this.updatedAt,
  });

  final int version;
  final DateTime? updatedAt;
  final List<OfficialAIChatTemplate> items;

  factory OfficialAIChatTemplateConfig.fromJson(
    Map<String, dynamic> json,
  ) => OfficialAIChatTemplateConfig(
    version: (json['version'] as num?)?.toInt() ?? 1,
    updatedAt: json['updated_at'] == null
        ? null
        : DateTime.tryParse(json['updated_at'] as String),
    items: (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              OfficialAIChatTemplate.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false),
  );

  Map<String, dynamic> toJson() => {
    'version': version,
    if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };
}
