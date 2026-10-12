import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:omni_ai/features/run_history/models/process_run_record.dart';
import 'package:omni_ai/features/run_history/repositories/run_history_repository.dart';
import 'package:omni_ai/features/system_core/models/system_core_process_state.dart';

typedef ProcessRunIdFactory = String Function();

class RunHistoryRecorder {
  RunHistoryRecorder({
    required Stream<SystemCoreProcessState> processStates,
    required this._repository,
    ProcessRunIdFactory? idFactory,
  }) : _idFactory = idFactory ?? _defaultIdFactory {
    _subscription = processStates.listen(_recordState);
  }

  final RunHistoryRepository _repository;
  final ProcessRunIdFactory _idFactory;
  late final StreamSubscription<SystemCoreProcessState> _subscription;

  ProcessRunRecord? _activeRecord;
  int _observedLogCount = 0;
  final List<ProcessRunRecord> _writeQueue = [];
  Completer<void>? _drainCompleter;
  bool _disposed = false;

  void _recordState(SystemCoreProcessState state) {
    if (_disposed) return;

    if (state.status == SystemCoreProcessStatus.starting) {
      if (state.logEntries.isEmpty) return;

      final startEntry = state.logEntries.last;
      _observedLogCount = state.logEntries.length;
      _activeRecord = ProcessRunRecord(
        id: _idFactory(),
        startedAt: startEntry.timestamp,
        status: state.status,
        logEntries: [startEntry],
      );
      _save(_activeRecord!);
      return;
    }

    final activeRecord = _activeRecord;
    if (activeRecord == null) return;

    final newEntries = state.logEntries.skip(_observedLogCount).toList();
    _observedLogCount = state.logEntries.length;
    final isFinished = _isFinished(state.status);
    final lastEventAt = newEntries.isEmpty
        ? activeRecord.finishedAt
        : newEntries.last.timestamp;
    final updatedRecord = activeRecord.copyWith(
      status: state.status,
      logEntries: [...activeRecord.logEntries, ...newEntries],
      finishedAt: isFinished ? lastEventAt : null,
      errorMessage: state.errorMessage,
      clearError:
          state.status != SystemCoreProcessStatus.failed &&
          state.status != SystemCoreProcessStatus.timeout,
    );

    _activeRecord = isFinished ? null : updatedRecord;
    _save(updatedRecord);
  }

  Future<void> flush() {
    debugPrint('RUN_HISTORY_FLUSH: pending=${_drainCompleter != null}, queued=${_writeQueue.length}');
    return _drainCompleter?.future ?? Future<void>.value();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    debugPrint('RUN_HISTORY_DISPOSE: before subscription cancel');
    await _subscription.cancel();
    debugPrint('RUN_HISTORY_DISPOSE: after subscription cancel');
    await flush();
    debugPrint('RUN_HISTORY_DISPOSE: after flush');
  }

  void _save(ProcessRunRecord record) {
    _writeQueue.add(record);
    if (_drainCompleter != null) return;

    final completer = Completer<void>();
    _drainCompleter = completer;
    unawaited(_drainWriteQueue(completer));
  }

  Future<void> _drainWriteQueue(Completer<void> completer) async {
    debugPrint('RUN_HISTORY_DRAIN: started');
    try {
      while (_writeQueue.isNotEmpty) {
        final record = _writeQueue.removeAt(0);
        debugPrint('RUN_HISTORY_DRAIN: saving ${record.id}, remaining=${_writeQueue.length}');
        await _repository.save(record);
        debugPrint('RUN_HISTORY_DRAIN: saved ${record.id}');
      }
      debugPrint('RUN_HISTORY_DRAIN: queue empty, completing');
      completer.complete();
      debugPrint('RUN_HISTORY_DRAIN: completer completed');
    } on Object catch (error, stackTrace) {
      debugPrint('RUN_HISTORY_DRAIN: failed $error');
      completer.completeError(error, stackTrace);
    } finally {
      debugPrint('RUN_HISTORY_DRAIN: finally, queued=${_writeQueue.length}');
      if (identical(_drainCompleter, completer)) {
        _drainCompleter = null;
      }
    }
  }

  static bool _isFinished(SystemCoreProcessStatus status) =>
      status == SystemCoreProcessStatus.completed ||
      status == SystemCoreProcessStatus.failed ||
      status == SystemCoreProcessStatus.cancelled ||
      status == SystemCoreProcessStatus.timeout;
}

String _defaultIdFactory() => 'run-${DateTime.now().microsecondsSinceEpoch}';
