import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

/// Mutable key store for a user's own OpenRouter account.
abstract interface class OpenRouterApiKeyStore implements OpenRouterApiKeySource {
  Future<void> writeApiKey(String apiKey);
  Future<void> deleteApiKey();
}

/// Stores the user's personal key using the platform secure-storage facility.
class SecureStorageOpenRouterApiKeySource implements OpenRouterApiKeyStore {
  SecureStorageOpenRouterApiKeySource({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const storageKey = 'omni_ai.openrouter_api_key.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readApiKey() async {
    final value = await _storage.read(key: storageKey);
    final key = value?.trim();
    return key == null || key.isEmpty ? null : key;
  }

  @override
  Future<void> writeApiKey(String apiKey) =>
      _storage.write(key: storageKey, value: apiKey.trim());

  @override
  Future<void> deleteApiKey() => _storage.delete(key: storageKey);
}
