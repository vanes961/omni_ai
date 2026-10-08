abstract interface class GeminiApiKeySource {
  Future<String?> readApiKey();
}
