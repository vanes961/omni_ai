import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/ai_memory/data/shared_preferences_ai_memory_repository.dart';
import 'package:omni_ai/features/ai_memory/models/ai_memory.dart';

void main() {
  group('SharedPreferencesAIMemoryRepository', () {
    test(
      'persists explicit memories and restores them after recreation',
      () async {
        final store = _MemoryStringStore();
        final repository = SharedPreferencesAIMemoryRepository(store: store);
        final memory = AIMemory(
          id: 'memory-1',
          content: 'Prefers concise answers',
          createdAt: DateTime.utc(2026, 1, 2),
        );

        await repository.save(memory);
        final restored = await SharedPreferencesAIMemoryRepository(
          store: store,
        ).getAll();

        expect(restored, hasLength(1));
        expect(restored.single.toJson(), memory.toJson());
        expect(
          jsonDecode(
            store.values[SharedPreferencesAIMemoryRepository.storageKey]!,
          ),
          isA<Map<String, dynamic>>(),
        );
        await repository.dispose();
      },
    );

    test('deletes only the requested memory', () async {
      final repository = SharedPreferencesAIMemoryRepository(
        store: _MemoryStringStore(),
      );
      await repository.save(
        AIMemory(
          id: 'keep',
          content: 'Keep this',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await repository.save(
        AIMemory(
          id: 'remove',
          content: 'Remove this',
          createdAt: DateTime.utc(2026, 1, 2),
        ),
      );

      await repository.delete('remove');

      expect((await repository.getAll()).map((memory) => memory.id), ['keep']);
      await repository.dispose();
    });

    test('rejects empty and overlong memories', () async {
      final repository = SharedPreferencesAIMemoryRepository(
        store: _MemoryStringStore(),
        maxMemoryCharacters: 5,
      );
      final now = DateTime.utc(2026);
      expect(
        () => repository.save(
          AIMemory(id: 'empty', content: '  ', createdAt: now),
        ),
        throwsArgumentError,
      );
      expect(
        () => repository.save(
          AIMemory(id: 'long', content: '123456', createdAt: now),
        ),
        throwsArgumentError,
      );
      expect(await repository.getAll(), isEmpty);
      await repository.dispose();
    });

    test('limits number of records and keeps the newest memories', () async {
      final repository = SharedPreferencesAIMemoryRepository(
        store: _MemoryStringStore(),
        maxMemories: 2,
      );
      for (var day = 1; day <= 3; day++) {
        await repository.save(
          AIMemory(
            id: 'm$day',
            content: 'memory $day',
            createdAt: DateTime.utc(2026, 1, day),
          ),
        );
      }

      expect((await repository.getAll()).map((memory) => memory.id), [
        'm3',
        'm2',
      ]);
      await repository.dispose();
    });

    test(
      'clears malformed storage instead of returning corrupt data',
      () async {
        final store = _MemoryStringStore()
          ..values[SharedPreferencesAIMemoryRepository.storageKey] = '{broken';
        final repository = SharedPreferencesAIMemoryRepository(store: store);

        expect(await repository.getAll(), isEmpty);
        expect(
          store.values.containsKey(
            SharedPreferencesAIMemoryRepository.storageKey,
          ),
          isFalse,
        );
        await repository.dispose();
      },
    );
  });
}

class _MemoryStringStore implements AIMemoryStringStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
