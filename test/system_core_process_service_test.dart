import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/system_core/models/system_core_process_state.dart';
import 'package:omni_ai/features/system_core/services/system_core_process_service.dart';

void main() {
  group('SystemCoreProcessService', () {
    final timestamp = DateTime(2026, 10, 8, 12, 30);

    test('transitions from starting through running to completed', () async {
      final service = SystemCoreProcessService(
        clock: () => timestamp,
        runner: (context) async {
          context.log(
            'PROCESS STEP COMPLETE',
            level: SystemCoreLogLevel.success,
          );
        },
      );
      addTearDown(service.dispose);
      final statuses = _recordStatuses(service);

      await service.start();

      expect(statuses, [
        SystemCoreProcessStatus.starting,
        SystemCoreProcessStatus.running,
        SystemCoreProcessStatus.completed,
      ]);
      expect(service.state.logEntries.last.timestamp, timestamp);
      expect(service.state.logEntries.last.message, 'AUTO-PROCESS COMPLETED');
      expect(service.state.errorMessage, isNull);
    });

    test('transitions from running to failed and records the error', () async {
      final service = SystemCoreProcessService(
        clock: () => timestamp,
        runner: (_) async => throw StateError('backend unavailable'),
      );
      addTearDown(service.dispose);
      final statuses = _recordStatuses(service);

      await service.start();

      expect(statuses, [
        SystemCoreProcessStatus.starting,
        SystemCoreProcessStatus.running,
        SystemCoreProcessStatus.failed,
      ]);
      expect(service.state.errorMessage, 'Bad state: backend unavailable');
      expect(service.state.logEntries.last.level, SystemCoreLogLevel.error);
      expect(service.state.logEntries.last.timestamp, timestamp);
    });

    test('can be cancelled while starting', () async {
      var runnerCalled = false;
      final service = SystemCoreProcessService(
        runner: (_) async {
          runnerCalled = true;
        },
      );
      addTearDown(service.dispose);
      final statuses = _recordStatuses(service);

      final start = service.start();
      service.cancel();
      await start;

      expect(statuses, [
        SystemCoreProcessStatus.starting,
        SystemCoreProcessStatus.cancelled,
      ]);
      expect(runnerCalled, isFalse);
    });

    test('can be cancelled while running', () async {
      final runnerStarted = Completer<void>();
      final service = SystemCoreProcessService(
        runner: (context) async {
          runnerStarted.complete();
          await context.cancellationRequested;
        },
      );
      addTearDown(service.dispose);
      final statuses = _recordStatuses(service);

      final start = service.start();
      await runnerStarted.future;
      service.cancel();
      await start;

      expect(statuses, [
        SystemCoreProcessStatus.starting,
        SystemCoreProcessStatus.running,
        SystemCoreProcessStatus.cancelled,
      ]);
      expect(service.state.logEntries.last.message, 'AUTO-PROCESS CANCELLED');
    });
  });
}

List<SystemCoreProcessStatus> _recordStatuses(
  SystemCoreProcessService service,
) {
  final statuses = <SystemCoreProcessStatus>[];
  service.states.listen((state) {
    if (statuses.isEmpty || statuses.last != state.status) {
      statuses.add(state.status);
    }
  });
  return statuses;
}
