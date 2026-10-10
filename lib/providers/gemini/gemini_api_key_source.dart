abstract interface class GeminiApiKeySource {
  Future<String?> readApiKey();
}

/// Development/test only: values supplied via --dart-define are embedded
/// in the compiled application and must not be used for production secrets.
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

/// Safe default for app builds: no cloud credential is bundled into the APK.
/// Production cloud access should be supplied by a secure runtime/backend
/// integration rather than a compile-time --dart-define value.
class UnconfiguredGeminiApiKeySource implements GeminiApiKeySource {
  const UnconfiguredGeminiApiKeySource();

  @override
  Future<String?> readApiKey() async => null;
}
