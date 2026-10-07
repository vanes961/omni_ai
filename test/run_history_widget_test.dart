import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/run_history/data/in_memory_run_history_repository.dart';
import 'package:omni_ai/features/run_history/models/process_run_record.dart';
import 'package:omni_ai/features/run_history/presentation/run_history_page.dart';
import 'package:omni_ai/features/system_core/models/system_core_process_state.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_page.dart';

void main() {
  testWidgets('opens run history from the system core page', (tester) async {
    final repository = InMemoryRunHistoryRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(home: SystemCorePage(historyRepository: repository)),
    );

    await tester.tap(find.byTooltip('Run history'));
    await tester.pumpAndSettle();

    expect(find.text('RUN HISTORY'), findsOneWidget);
    expect(find.text('NO RUNS RECORDED'), findsOneWidget);
  });

  testWidgets('shows log details and deletes a run', (tester) async {
    final repository = InMemoryRunHistoryRepository();
    addTearDown(repository.dispose);
    await repository.save(
      ProcessRunRecord(
        id: 'run-42',
        startedAt: DateTime(2026, 10, 8, 12, 30),
        finishedAt: DateTime(2026, 10, 8, 12, 31),
        status: SystemCoreProcessStatus.completed,
        logEntries: [
          SystemCoreLogEntry(
            timestamp: DateTime(2026, 10, 8, 12, 30),
            message: 'TASK COMPLETE',
            level: SystemCoreLogLevel.success,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: RunHistoryPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.textContaining('run-42'), findsOneWidget);

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.text('TASK COMPLETE'), findsOneWidget);
    expect(find.text('DURATION  01:00'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete run'));
    await tester.pumpAndSettle();
    expect(find.text('NO RUNS RECORDED'), findsOneWidget);
  });
}
