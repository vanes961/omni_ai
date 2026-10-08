import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class UserPreferences {
  UserPreferences();

  List<String> categories = [];
  List<String> favoriteTitles = [];
  List<String> voiceDubbing = [];
  List<String> tgChannels = [];

  Map<String, dynamic> toJson() => {
    'categories': categories,
    'favoriteTitles': favoriteTitles,
    'voiceDubbing': voiceDubbing,
    'tgChannels': tgChannels,
  };

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences()
      ..categories = _stringList(json['categories'])
      ..favoriteTitles = _stringList(json['favoriteTitles'])
      ..voiceDubbing = _stringList(json['voiceDubbing'])
      ..tgChannels = _stringList(json['tgChannels']);
  }
}

abstract interface class UserPreferencesStore {
  Future<UserPreferences?> load();

  Future<void> save(UserPreferences preferences);
}

abstract interface class UserPreferencesStringStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> remove(String key);
}

class SharedPreferencesUserPreferencesStore implements UserPreferencesStore {
  SharedPreferencesUserPreferencesStore({UserPreferencesStringStore? store})
    : _store = store ?? _SharedPreferencesStringStore();

  static const String storageKey = 'omni_ai.user_preferences.v1';

  final UserPreferencesStringStore _store;

  @override
  Future<UserPreferences?> load() async {
    final encoded = await _store.read(storageKey);
    if (encoded == null) return null;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) throw const FormatException('Invalid profile.');
      return UserPreferences.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      await _store.remove(storageKey);
      return null;
    } on TypeError {
      await _store.remove(storageKey);
      return null;
    }
  }

  @override
  Future<void> save(UserPreferences preferences) {
    return _store.write(storageKey, jsonEncode(preferences.toJson()));
  }
}

class _SharedPreferencesStringStore implements UserPreferencesStringStore {
  SharedPreferencesAsync? _instance;

  SharedPreferencesAsync get _preferences =>
      _instance ??= SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) {
    return _preferences.setString(key, value);
  }

  @override
  Future<void> remove(String key) => _preferences.remove(key);
}

List<String> _stringList(Object? value) =>
    value is List ? value.whereType<String>().toList() : <String>[];
