class AIMemory {
  const AIMemory({
    required this.id,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String content;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'content': content,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory AIMemory.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final content = json['content'];
    final createdAt = json['createdAt'];
    if (id is! String ||
        id.isEmpty ||
        content is! String ||
        content.trim().isEmpty ||
        createdAt is! String) {
      throw const FormatException('Invalid AI memory record.');
    }

    return AIMemory(
      id: id,
      content: content,
      createdAt: DateTime.parse(createdAt),
    );
  }
}
