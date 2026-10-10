import 'package:shared_preferences/shared_preferences.dart';

import 'routing_ai_provider.dart';

/// Persists the user's explicit AI destination independently of profile data.
abstract interface class AIExecutionModeStore {
  Future<AIExecutionMode> load();

  Future<void> save(AIExecutionMode mode);
}

class SharedPreferencesAIExecutionModeStore implements AIExecutionModeStore {
  SharedPreferencesAIExecutionModeStore({
    Future<String?> Function(String key)? read,
    Future<void> Function(String key, String value)? write,
  }) : _read = read ?? _readSharedPreference,
       _write = write ?? _writeSharedPreference;

  static const storageKey = 'omni_ai.ai_execution_mode.v1';

  final Future<String?> Function(String key) _read;
  final Future<void> Function(String key, String value) _write;

  @override
  Future<AIExecutionMode> load() async {
    final stored = await _read(storageKey);
    return switch (stored) {
      'cloud' => AIExecutionMode.cloud,
      'local' => AIExecutionMode.local,
      _ => AIExecutionMode.local,
    };
  }

  @override
  Future<void> save(AIExecutionMode mode) =>
      _write(storageKey, mode.name);

  static Future<String?> _readSharedPreference(String key) =>
      SharedPreferencesAsync().getString(key);

  static Future<void> _writeSharedPreference(String key, String value) =>
      SharedPreferencesAsync().setString(key, value);
}
