class AIRequest {
  const AIRequest({
    required this.id,
    required this.prompt,
    this.systemInstruction,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String prompt;
  final String? systemInstruction;
  final Map<String, Object?> metadata;

  AIRequest copyWith({
    String? id,
    String? prompt,
    String? systemInstruction,
    bool clearSystemInstruction = false,
    Map<String, Object?>? metadata,
  }) {
    return AIRequest(
      id: id ?? this.id,
      prompt: prompt ?? this.prompt,
      systemInstruction: clearSystemInstruction
          ? null
          : systemInstruction ?? this.systemInstruction,
      metadata: metadata ?? this.metadata,
    );
  }
}
