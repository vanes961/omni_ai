import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_ai/features/news/data/news_interest_repository.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';

abstract interface class NewsProfileStringStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// Local preferences only; source credentials and network ingestion stay server-side.
class SharedPreferencesNewsInterestRepository
    implements NewsInterestRepository {
  SharedPreferencesNewsInterestRepository({NewsProfileStringStore? store})
    : _store = store ?? _SharedPreferencesNewsProfileStore();

  static const storageKey = 'omni_ai.news_interest_profile.v1';
  final NewsProfileStringStore _store;
  bool _disposed = false;

  @override
  Future<NewsInterestProfile> load() async {
    if (_disposed) {
      throw StateError('News interest repository has been disposed.');
    }
    final encoded = await _store.read(storageKey);
    if (encoded == null || encoded.isEmpty) return const NewsInterestProfile();

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map<String, dynamic>) {
        return NewsInterestProfile.fromJson(decoded);
      }
    } on FormatException {
      await _store.remove(storageKey);
      return const NewsInterestProfile();
    }
    await _store.remove(storageKey);
    return const NewsInterestProfile();
  }

  @override
  Future<void> save(NewsInterestProfile profile) async {
    if (_disposed) {
      throw StateError('News interest repository has been disposed.');
    }
    final normalized = NewsInterestProfile(
      topics: _normalize(profile.topics),
      languages: _normalize(profile.languages),
      regions: _normalize(profile.regions),
      includeCriticalOutsideInterests: profile.includeCriticalOutsideInterests,
    );
    await _store.write(storageKey, jsonEncode(normalized.toJson()));
  }

  List<String> _normalize(List<String> values) => values
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}

class _SharedPreferencesNewsProfileStore implements NewsProfileStringStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<void> remove(String key) => _preferences.remove(key);
}
