import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class MediaCatalogTokenSource {
  Future<String?> readToken();
}

abstract interface class MediaCatalogTokenStore
    implements MediaCatalogTokenSource {
  Future<void> saveToken(String token);
  Future<void> deleteToken();
}

/// Stores the user's own TMDB read-access token on the device.
///
/// A distributed APK must not contain a shared TMDB credential in
/// `--dart-define`; secure runtime storage keeps the token out of source code.
class SecureMediaCatalogTokenStore implements MediaCatalogTokenStore {
  SecureMediaCatalogTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const storageKey = 'omni_ai.tmdb_access_token.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() async {
    final value = await _storage.read(key: storageKey);
    final token = value?.trim();
    return token == null || token.isEmpty ? null : token;
  }

  @override
  Future<void> saveToken(String token) =>
      _storage.write(key: storageKey, value: token.trim());

  @override
  Future<void> deleteToken() => _storage.delete(key: storageKey);
}
