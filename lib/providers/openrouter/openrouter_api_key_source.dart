abstract interface class OpenRouterApiKeySource {
  Future<String?> readApiKey();
}

/// Development/test only. A --dart-define value is embedded in the binary and
/// must never be used as a shared production credential in a distributed APK.
class EnvironmentOpenRouterApiKeySource implements OpenRouterApiKeySource {
  const EnvironmentOpenRouterApiKeySource({
    this._apiKey = const String.fromEnvironment('OPENROUTER_API_KEY'),
  });

  final String _apiKey;

  @override
  Future<String?> readApiKey() async {
    final apiKey = _apiKey.trim();
    return apiKey.isEmpty ? null : apiKey;
  }
}

/// Safe default until a secure backend or user-owned runtime key is configured.
class UnconfiguredOpenRouterApiKeySource implements OpenRouterApiKeySource {
  const UnconfiguredOpenRouterApiKeySource();

  @override
  Future<String?> readApiKey() async => null;
}
