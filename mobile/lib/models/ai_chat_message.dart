class AIChatMessage {
  const AIChatMessage({required this.role, required this.content});

  final String role;
  final String content;

  factory AIChatMessage.fromJson(Map<String, dynamic> json) => AIChatMessage(
    role: json['role'] as String,
    content: json['content'] as String,
  );

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}
