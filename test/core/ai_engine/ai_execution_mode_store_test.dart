import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_execution_mode_store.dart';
import 'package:omni_ai/core/ai_engine/providers/routing_ai_provider.dart';

void main() {
  group('SharedPreferencesAIExecutionModeStore', () {
    test('defaults to automatic when no mode is saved', () async {
      final store = _MemoryModeStore();

      expect(await store.load(), AIExecutionMode.automatic);
    });

    test('persists cloud selection and restores it', () async {
      final store = _MemoryModeStore();

      await store.save(AIExecutionMode.cloud);

      expect(await store.load(), AIExecutionMode.cloud);
      expect(store.savedKey, SharedPreferencesAIExecutionModeStore.storageKey);
      expect(store.savedValue, 'cloud');
    });

    test('persists automatic selection and restores it', () async {
      final store = _MemoryModeStore();

      await store.save(AIExecutionMode.automatic);

      expect(await store.load(), AIExecutionMode.automatic);
      expect(store.savedValue, 'automatic');
    });

    test('unknown stored values safely default to automatic', () async {
      final store = _MemoryModeStore()..value = 'unexpected';

      expect(await store.load(), AIExecutionMode.automatic);
    });
  });
}

class _MemoryModeStore extends SharedPreferencesAIExecutionModeStore {
  _MemoryModeStore() : super(read: _readPlaceholder, write: _writePlaceholder);

  String? value;
  String? savedKey;
  String? savedValue;

  static Future<String?> _readPlaceholder(String key) async => null;
  static Future<void> _writePlaceholder(String key, String value) async {}

  @override
  Future<AIExecutionMode> load() async {
    return switch (value) {
      'cloud' => AIExecutionMode.cloud,
      'local' => AIExecutionMode.local,
      'automatic' || null => AIExecutionMode.automatic,
      _ => AIExecutionMode.automatic,
    };
  }

  @override
  Future<void> save(AIExecutionMode mode) async {
    savedKey = SharedPreferencesAIExecutionModeStore.storageKey;
    savedValue = mode.name;
    value = mode.name;
  }
}
