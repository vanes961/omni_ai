import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/system_core/models/system_core_process_state.dart';

void main() {
  group('SystemCoreProcessState', () {
    test('starts ready with DateTime-stamped initial log entries', () {
      final timestamps = List.generate(
        4,
        (index) => DateTime(2026, 10, 8, 12, 30, index),
      );
      var timestampIndex = 0;
      final state = SystemCoreProcessState.initial(
        clock: () => timestamps[timestampIndex++],
      );

      expect(state.status, SystemCoreProcessStatus.ready);
      expect(state.canStart, isTrue);
      expect(state.logEntries, hasLength(4));
      expect(state.logEntries.first.message, ' BOOTING OMNI_AI KERNEL...');
      expect(state.logEntries.map((entry) => entry.timestamp), timestamps);
    });
  });
}
