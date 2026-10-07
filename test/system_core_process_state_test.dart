import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/system_core/models/system_core_process_state.dart';

void main() {
  group('SystemCoreProcessState', () {
    test('starts ready with the initial log entries', () {
      final state = SystemCoreProcessState.initial();

      expect(state.status, SystemCoreProcessStatus.ready);
      expect(state.isRunning, isFalse);
      expect(state.logEntries, hasLength(4));
      expect(state.logEntries.first.message, ' BOOTING OMNI_AI KERNEL...');
    });

    test('start returns a running state with process logs', () {
      final state = SystemCoreProcessState.initial().start();

      expect(state.status, SystemCoreProcessStatus.running);
      expect(state.isRunning, isTrue);
      expect(state.logEntries.first.message, ' AUTO-PROCESS INITIALIZED');
    });

    test('starting an already running process preserves its state', () {
      final state = SystemCoreProcessState.initial().start();

      expect(state.start(), same(state));
    });
  });
}
