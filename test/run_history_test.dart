import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/run_history/data/in_memory_run_history_repository.dart';
import 'package:omni_ai/features/run_history/data/shared_preferences_run_history_repository.dart';
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

  group('SharedPreferencesRunHistoryRepository', () {
    test(
      'persists and restores run records with their complete log data',
      () async {
        final store = _FakeRunHistoryStringStore();
        final repository = SharedPreferencesRunHistoryRepository(store: store);
        final record = ProcessRunRecord(
          id: 'restored-run',
          startedAt: DateTime(2026, 10, 8, 12, 30),
          finishedAt: DateTime(2026, 10, 8, 12, 31),
          status: SystemCoreProcessStatus.failed,
          errorMessage: 'worker stopped',
          logEntries: [
            SystemCoreLogEntry(
              timestamp: DateTime(2026, 10, 8, 12, 30, 15),
              message: 'WORKER FAILED',
              level: SystemCoreLogLevel.error,
            ),
          ],
        );
        addTearDown(repository.dispose);

        await repository.save(record);
        final restoredRepository = SharedPreferencesRunHistoryRepository(
          store: store,
        );
        addTearDown(restoredRepository.dispose);
        final restored = (await restoredRepository.getAll()).single;

        expect(restored.id, record.id);
        expect(restored.startedAt, record.startedAt.toUtc());
        expect(restored.finishedAt, record.finishedAt!.toUtc());
        expect(restored.status, record.status);
        expect(restored.errorMessage, record.errorMessage);
        expect(
          restored.logEntries.single.timestamp,
          record.logEntries.single.timestamp.toUtc(),
        );
        expect(restored.logEntries.single.message, 'WORKER FAILED');
        expect(restored.logEntries.single.level, SystemCoreLogLevel.error);
      },
    );

    test('keeps only the newest records up to the retention limit', () async {
      final store = _FakeRunHistoryStringStore();
      final repository = SharedPreferencesRunHistoryRepository(
        store: store,
        maxRecords: 3,
      );
      addTearDown(repository.dispose);

      for (var index = 0; index < 5; index++) {
        await repository.save(
          _record('run-$index', DateTime(2026, 10, 8, 12, index)),
        );
      }

      expect((await repository.getAll()).map((record) => record.id), [
        'run-4',
        'run-3',
        'run-2',
      ]);
    });

    test(
      'removes malformed data and skips invalid records without losing valid ones',
      () async {
        final store = _FakeRunHistoryStringStore();
        final repository = SharedPreferencesRunHistoryRepository(store: store);
        addTearDown(repository.dispose);

        await store.write(
          SharedPreferencesRunHistoryRepository.storageKey,
          '{bad',
        );
        expect(await repository.getAll(), isEmpty);
        expect(
          await store.read(SharedPreferencesRunHistoryRepository.storageKey),
          isNull,
        );

        await store.write(
          SharedPreferencesRunHistoryRepository.storageKey,
          jsonEncode({
            'version': 1,
            'records': [
              _record('valid', DateTime(2026, 10, 8)).toJson(),
              {'id': 'invalid'},
            ],
          }),
        );
        expect((await repository.getAll()).map((record) => record.id), [
          'valid',
        ]);
        expect(
          jsonDecode(
            (await store.read(
              SharedPreferencesRunHistoryRepository.storageKey,
            ))!,
          )['records'],
          hasLength(1),
        );
      },
    );

    test('preserves data written with an unsupported format version', () async {
      final store = _FakeRunHistoryStringStore();
      final repository = SharedPreferencesRunHistoryRepository(store: store);
      addTearDown(repository.dispose);
      const encoded = '{"version":2,"records":[]}';
      await store.write(
        SharedPreferencesRunHistoryRepository.storageKey,
        encoded,
      );

      await expectLater(repository.getAll(), throwsFormatException);

      expect(
        await store.read(SharedPreferencesRunHistoryRepository.storageKey),
        encoded,
      );
    });

    test(
      'deletes persistent records and publishes updated snapshots',
      () async {
        final store = _FakeRunHistoryStringStore();
        final repository = SharedPreferencesRunHistoryRepository(store: store);
        addTearDown(repository.dispose);
        final snapshots = <List<ProcessRunRecord>>[];
        final subscription = repository.watch().listen(snapshots.add);
        addTearDown(subscription.cancel);

        await repository.save(_record('to-delete', DateTime(2026, 10, 8)));
        await repository.delete('to-delete');
        await Future<void>.delayed(Duration.zero);

        expect(await repository.getAll(), isEmpty);
        expect(snapshots.last, isEmpty);
      },
    );
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

class _FakeRunHistoryStringStore implements RunHistoryStringStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}
