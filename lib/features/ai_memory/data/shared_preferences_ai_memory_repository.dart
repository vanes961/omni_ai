import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_ai/features/ai_memory/models/ai_memory.dart';
import 'package:omni_ai/features/ai_memory/repositories/ai_memory_repository.dart';

abstract interface class AIMemoryStringStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> remove(String key);
}

/// Local, bounded storage for memories the user explicitly chooses to save.
class SharedPreferencesAIMemoryRepository implements AIMemoryRepository {
  SharedPreferencesAIMemoryRepository({
    AIMemoryStringStore? store,
    this.maxMemories = defaultMaxMemories,
    this.maxMemoryCharacters = defaultMaxMemoryCharacters,
  }) : _store = store ?? _SharedPreferencesMemoryStringStore() {
    if (maxMemories <= 0) {
      throw ArgumentError.value(
        maxMemories,
        'maxMemories',
        'Must be positive.',
      );
    }
    if (maxMemoryCharacters <= 0) {
      throw ArgumentError.value(
        maxMemoryCharacters,
        'maxMemoryCharacters',
        'Must be positive.',
      );
    }
  }

  static const int defaultMaxMemories = 100;
  static const int defaultMaxMemoryCharacters = 500;
  static const String storageKey = 'omni_ai.explicit_memories.v1';
  static const int _formatVersion = 1;

  final AIMemoryStringStore _store;
  final int maxMemories;
  final int maxMemoryCharacters;

  Future<void> _operations = Future<void>.value();
  bool _disposed = false;

  @override
  Future<List<AIMemory>> getAll() => _serialize(_readMemories);

  @override
  Future<void> save(AIMemory memory) {
    final content = memory.content.trim();
    if (content.isEmpty) {
      throw ArgumentError.value(
        memory.content,
        'content',
        'Must not be empty.',
      );
    }
    if (content.length > maxMemoryCharacters) {
      throw ArgumentError.value(
        memory.content,
        'content',
        'Must be at most $maxMemoryCharacters characters.',
      );
    }
    if (memory.id.trim().isEmpty) {
      throw ArgumentError.value(memory.id, 'id', 'Must not be empty.');
    }

    return _serialize(() async {
      if (_disposed) return;
      final records = await _readMemories();
      records.removeWhere((existing) => existing.id == memory.id);
      records.add(
        AIMemory(id: memory.id, content: content, createdAt: memory.createdAt),
      );
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final retained = records.take(maxMemories).toList(growable: false);
      await _writeMemories(retained);
    });
  }

  @override
  Future<void> delete(String id) {
    return _serialize(() async {
      if (_disposed) return;
      final records = await _readMemories();
      final previousLength = records.length;
      records.removeWhere((memory) => memory.id == id);
      if (records.length == previousLength) return;
      await _writeMemories(records);
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await _operations;
    _disposed = true;
  }

  Future<List<AIMemory>> _readMemories() async {
    final encoded = await _store.read(storageKey);
    if (encoded == null || encoded.isEmpty) return [];

    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      await _store.remove(storageKey);
      return [];
    }

    if (decoded is! Map<String, dynamic> || decoded['records'] is! List) {
      await _store.remove(storageKey);
      return [];
    }
    if (decoded['version'] != _formatVersion) {
      throw const FormatException('Unsupported AI memory data version.');
    }

    var skippedInvalidRecord = false;
    final records = <AIMemory>[];
    for (final rawRecord in decoded['records'] as List) {
      try {
        final memory = AIMemory.fromJson(
          Map<String, Object?>.from(rawRecord as Map),
        );
        if (memory.content.trim().isEmpty ||
            memory.content.length > maxMemoryCharacters) {
          skippedInvalidRecord = true;
          continue;
        }
        records.add(memory);
      } on Object {
        skippedInvalidRecord = true;
      }
    }

    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final retained = records.take(maxMemories).toList();
    if (skippedInvalidRecord || retained.length != records.length) {
      await _writeMemories(retained);
    }
    return retained;
  }

  Future<void> _writeMemories(List<AIMemory> records) {
    return _store.write(
      storageKey,
      jsonEncode({
        'version': _formatVersion,
        'records': [for (final memory in records) memory.toJson()],
      }),
    );
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operations = _operations.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

class _SharedPreferencesMemoryStringStore implements AIMemoryStringStore {
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
