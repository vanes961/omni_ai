class AIResponse {
  const AIResponse({
    required this.requestId,
    required this.text,
    required this.providerId,
    required this.generatedAt,
    this.metadata = const <String, Object?>{},
  });

  final String requestId;
  final String text;
  final String providerId;
  final DateTime generatedAt;
  final Map<String, Object?> metadata;
}
