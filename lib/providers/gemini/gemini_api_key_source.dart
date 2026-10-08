abstract interface class GeminiApiKeySource {
  Future<String?> readApiKey();
}

class EnvironmentGeminiApiKeySource implements GeminiApiKeySource {
  const EnvironmentGeminiApiKeySource({
    this._apiKey = const String.fromEnvironment('GEMINI_API_KEY'),
  });

  final String _apiKey;

  @override
  Future<String?> readApiKey() async {
    final apiKey = _apiKey.trim();
    return apiKey.isEmpty ? null : apiKey;
  }
}
