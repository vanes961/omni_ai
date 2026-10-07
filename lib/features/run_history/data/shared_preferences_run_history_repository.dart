import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_ai/features/run_history/models/process_run_record.dart';
import 'package:omni_ai/features/run_history/repositories/run_history_repository.dart';

abstract interface class RunHistoryStringStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> remove(String key);
}

class SharedPreferencesRunHistoryRepository implements RunHistoryRepository {
  SharedPreferencesRunHistoryRepository({
    RunHistoryStringStore? store,
    this.maxRecords = defaultMaxRecords,
  }) : _store = store ?? _SharedPreferencesStringStore() {
    if (maxRecords <= 0) {
      throw ArgumentError.value(maxRecords, 'maxRecords', 'Must be positive.');
    }
  }

  static const int defaultMaxRecords = 100;
  static const String storageKey = 'omni_ai.run_history.v1';
  static const int _formatVersion = 1;

  final RunHistoryStringStore _store;
  final int maxRecords;
  final StreamController<List<ProcessRunRecord>> _changes =
      StreamController<List<ProcessRunRecord>>.broadcast(sync: true);

  Future<void> _operations = Future<void>.value();
  bool _disposed = false;

  @override
  Stream<List<ProcessRunRecord>> watch() {
    return Stream<List<ProcessRunRecord>>.multi((controller) {
      var active = true;
      final subscription = _changes.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () {
        active = false;
        return subscription.cancel();
      };
      getAll().then(
        (records) {
          if (active) controller.add(records);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (active) controller.addError(error, stackTrace);
        },
      );
    });
  }

  @override
  Future<List<ProcessRunRecord>> getAll() {
    return _serialize(_readRecords);
  }

  @override
  Future<void> save(ProcessRunRecord record) {
    return _serialize(() async {
      if (_disposed) return;
      final records = await _readRecords();
      records.removeWhere((existing) => existing.id == record.id);
      records.add(record);
      final retained = _sortAndLimit(records);
      await _writeRecords(retained);
      _changes.add(List.unmodifiable(retained));
    });
  }

  @override
  Future<void> delete(String id) {
    return _serialize(() async {
      if (_disposed) return;
      final records = await _readRecords();
      if (!records.any((record) => record.id == id)) return;
      records.removeWhere((record) => record.id == id);
      final retained = _sortAndLimit(records);
      await _writeRecords(retained);
      _changes.add(List.unmodifiable(retained));
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await _operations;
    _disposed = true;
    await _changes.close();
  }

  Future<List<ProcessRunRecord>> _readRecords() async {
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
      throw const FormatException('Unsupported run history data version.');
    }

    var skippedInvalidRecord = false;
    final records = <ProcessRunRecord>[];
    for (final rawRecord in decoded['records'] as List) {
      try {
        records.add(
          ProcessRunRecord.fromJson(
            Map<String, Object?>.from(rawRecord as Map),
          ),
        );
      } on Object {
        skippedInvalidRecord = true;
      }
    }

    final retained = _sortAndLimit(records);
    if (skippedInvalidRecord || retained.length != records.length) {
      await _writeRecords(retained);
    }
    return retained;
  }

  Future<void> _writeRecords(List<ProcessRunRecord> records) {
    return _store.write(
      storageKey,
      jsonEncode({
        'version': _formatVersion,
        'records': [for (final record in records) record.toJson()],
      }),
    );
  }

  List<ProcessRunRecord> _sortAndLimit(Iterable<ProcessRunRecord> records) {
    final sorted = records.toList()
      ..sort((first, second) => second.startedAt.compareTo(first.startedAt));
    return sorted.take(maxRecords).toList();
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

class _SharedPreferencesStringStore implements RunHistoryStringStore {
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
