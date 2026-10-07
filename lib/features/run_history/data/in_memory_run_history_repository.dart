import 'dart:async';

import 'package:omni_ai/features/run_history/models/process_run_record.dart';
import 'package:omni_ai/features/run_history/repositories/run_history_repository.dart';

class InMemoryRunHistoryRepository implements RunHistoryRepository {
  final Map<String, ProcessRunRecord> _records = {};
  final StreamController<List<ProcessRunRecord>> _changes =
      StreamController<List<ProcessRunRecord>>.broadcast(sync: true);
  bool _disposed = false;

  @override
  Stream<List<ProcessRunRecord>> watch() {
    return Stream<List<ProcessRunRecord>>.multi((controller) {
      controller.add(_snapshot());
      final subscription = _changes.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<List<ProcessRunRecord>> getAll() async => _snapshot();

  @override
  Future<void> save(ProcessRunRecord record) async {
    if (_disposed) return;
    _records[record.id] = record;
    _changes.add(_snapshot());
  }

  @override
  Future<void> delete(String id) async {
    if (_disposed || _records.remove(id) == null) return;
    _changes.add(_snapshot());
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _changes.close();
  }

  List<ProcessRunRecord> _snapshot() {
    final records = _records.values.toList()
      ..sort((first, second) => second.startedAt.compareTo(first.startedAt));
    return List.unmodifiable(records);
  }
}
