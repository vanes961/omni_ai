import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Reads and stores a user's PoiskKino API key without embedding it in the APK.
abstract interface class PoiskKinoApiKeyStore {
  Future<String?> readApiKey();
  Future<void> saveApiKey(String apiKey);
  Future<void> deleteApiKey();
}

class SecurePoiskKinoApiKeyStore implements PoiskKinoApiKeyStore {
  SecurePoiskKinoApiKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const storageKey = 'omni_ai.poiskkino_api_key.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readApiKey() async {
    final value = await _storage.read(key: storageKey);
    final key = value?.trim();
    return key == null || key.isEmpty ? null : key;
  }

  @override
  Future<void> saveApiKey(String apiKey) =>
      _storage.write(key: storageKey, value: apiKey.trim());

  @override
  Future<void> deleteApiKey() => _storage.delete(key: storageKey);
}
