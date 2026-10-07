import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/run_history/data/in_memory_run_history_repository.dart';
import 'package:omni_ai/features/run_history/models/process_run_record.dart';
import 'package:omni_ai/features/run_history/services/run_history_recorder.dart';
import 'package:omni_ai/features/system_core/models/system_core_process_state.dart';
import 'package:omni_ai/features/system_core/services/system_core_process_service.dart';

void main() {
  group('RunHistoryRecorder', () {
    final timestamp = DateTime(2026, 10, 8, 12, 30);

    test('records a completed run with only its dynamic events', () async {
      final repository = InMemoryRunHistoryRepository();
      final service = SystemCoreProcessService(
        clock: () => timestamp,
        runner: (context) async {
          context.log('TASK EXECUTED', level: SystemCoreLogLevel.success);
        },
      );
      final recorder = RunHistoryRecorder(
        processStates: service.states,
        repository: repository,
        idFactory: () => 'run-1',
      );
      addTearDown(() async {
        await recorder.dispose();
        await service.dispose();
        await repository.dispose();
      });

      await service.start();
      await recorder.flush();

      final records = await repository.getAll();
      expect(records, hasLength(1));
      expect(records.single.id, 'run-1');
      expect(records.single.status, SystemCoreProcessStatus.completed);
      expect(records.single.startedAt, timestamp);
      expect(records.single.finishedAt, timestamp);
      expect(records.single.duration, Duration.zero);
      expect(records.single.logEntries.map((entry) => entry.message), [
        'AUTO-PROCESS STARTING...',
        'AUTO-PROCESS INITIALIZED',
        'TASK EXECUTED',
        'AUTO-PROCESS COMPLETED',
      ]);
    });

    test('records a failed run and its error message', () async {
      final repository = InMemoryRunHistoryRepository();
      final service = SystemCoreProcessService(
        clock: () => timestamp,
        runner: (_) async => throw StateError('backend unavailable'),
      );
      final recorder = RunHistoryRecorder(
        processStates: service.states,
        repository: repository,
        idFactory: () => 'run-failed',
      );
      addTearDown(() async {
        await recorder.dispose();
        await service.dispose();
        await repository.dispose();
      });

      await service.start();
      await recorder.flush();

      final record = (await repository.getAll()).single;
      expect(record.status, SystemCoreProcessStatus.failed);
      expect(record.errorMessage, 'Bad state: backend unavailable');
      expect(record.logEntries.last.level, SystemCoreLogLevel.error);
      expect(record.finishedAt, timestamp);
    });

    test('records a cancelled run while it is running', () async {
      final runnerStarted = Completer<void>();
      final repository = InMemoryRunHistoryRepository();
      final service = SystemCoreProcessService(
        clock: () => timestamp,
        runner: (context) async {
          runnerStarted.complete();
          await context.cancellationRequested;
        },
      );
      final recorder = RunHistoryRecorder(
        processStates: service.states,
        repository: repository,
        idFactory: () => 'run-cancelled',
      );
      addTearDown(() async {
        await recorder.dispose();
        await service.dispose();
        await repository.dispose();
      });

      final start = service.start();
      await runnerStarted.future;
      service.cancel();
      await start;
      await recorder.flush();

      final record = (await repository.getAll()).single;
      expect(record.status, SystemCoreProcessStatus.cancelled);
      expect(record.logEntries.last.message, 'AUTO-PROCESS CANCELLED');
      expect(record.finishedAt, timestamp);
    });

    test('keeps logs isolated between consecutive runs', () async {
      var runNumber = 0;
      var idNumber = 0;
      final repository = InMemoryRunHistoryRepository();
      final service = SystemCoreProcessService(
        clock: () => timestamp,
        runner: (context) async {
          runNumber++;
          context.log('TASK $runNumber');
        },
      );
      final recorder = RunHistoryRecorder(
        processStates: service.states,
        repository: repository,
        idFactory: () => 'run-${++idNumber}',
      );
      addTearDown(() async {
        await recorder.dispose();
        await service.dispose();
        await repository.dispose();
      });

      await service.start();
      await service.start();
      await recorder.flush();

      final records = await repository.getAll();
      expect(records, hasLength(2));
      expect(records.map((record) => record.id).toSet(), {'run-1', 'run-2'});
      final secondRun = records.singleWhere((record) => record.id == 'run-2');
      expect(
        secondRun.logEntries.map((entry) => entry.message),
        contains('TASK 2'),
      );
      expect(
        secondRun.logEntries.map((entry) => entry.message),
        isNot(contains('TASK 1')),
      );
    });
  });

  group('InMemoryRunHistoryRepository', () {
    test('sorts records newest first and publishes delete updates', () async {
      final repository = InMemoryRunHistoryRepository();
      addTearDown(repository.dispose);
      final snapshots = <List<ProcessRunRecord>>[];
      final subscription = repository.watch().listen(snapshots.add);
      addTearDown(subscription.cancel);
      final earlier = _record('earlier', DateTime(2026, 10, 7));
      final later = _record('later', DateTime(2026, 10, 8));

      await repository.save(earlier);
      await repository.save(later);
      await repository.delete('later');
      await Future<void>.delayed(Duration.zero);

      expect((await repository.getAll()).map((record) => record.id), [
        'earlier',
      ]);
      expect(snapshots, hasLength(4));
      expect(snapshots[0], isEmpty);
      expect(snapshots[2].map((record) => record.id), ['later', 'earlier']);
      expect(snapshots[3].map((record) => record.id), ['earlier']);
    });
  });
}

ProcessRunRecord _record(String id, DateTime startedAt) {
  return ProcessRunRecord(
    id: id,
    startedAt: startedAt,
    status: SystemCoreProcessStatus.completed,
    logEntries: const [],
  );
}
