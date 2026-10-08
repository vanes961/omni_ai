import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/models/ai_error.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:omni_ai/features/run_history/data/in_memory_run_history_repository.dart';
import 'package:omni_ai/features/system_core/models/system_core_process_state.dart';
import 'package:omni_ai/features/system_core/services/ai_process_orchestrator.dart';
import 'package:omni_ai/features/system_core/services/system_core_process_service.dart';

void main() {
  test(
    'completes an AI run and records metadata, duration, and process states',
    () async {
      final harness = _OrchestratorHarness(provider: _FakeProvider());
      addTearDown(harness.dispose);
      final states = harness.watchProcessStates();

      final response = await harness.orchestrator.execute(_request('success'));

      expect(response.text, 'generated response');
      expect(states, [
        SystemCoreProcessStatus.starting,
        SystemCoreProcessStatus.running,
        SystemCoreProcessStatus.completed,
      ]);
      final record = (await harness.repository.getAll()).single;
      expect(record.id, 'run-1');
      expect(record.status, SystemCoreProcessStatus.completed);
      expect(record.duration, isNotNull);
      expect(
        record.logEntries.map((entry) => entry.message),
        containsAll(['AI REQUEST success', 'AI PROVIDER fake']),
      );
    },
  );

  test('records provider failure as a failed System Core run', () async {
    final harness = _OrchestratorHarness(
      provider: _FakeProvider(error: StateError('provider offline')),
    );
    addTearDown(harness.dispose);
    final states = harness.watchProcessStates();

    await expectLater(
      harness.orchestrator.execute(_request('failure')),
      throwsA(
        isA<AIEngineException>().having(
          (error) => error.error.code,
          'code',
          AIErrorCode.provider,
        ),
      ),
    );

    expect(states.last, SystemCoreProcessStatus.failed);
    final record = (await harness.repository.getAll()).single;
    expect(record.status, SystemCoreProcessStatus.failed);
    expect(record.errorMessage, contains('provider offline'));
    expect(record.finishedAt, isNotNull);
  });

  test('records caller cancellation as cancelled', () async {
    final provider = _FakeProvider(waitForCancellation: true);
    final harness = _OrchestratorHarness(provider: provider);
    addTearDown(harness.dispose);
    final states = harness.watchProcessStates();
    final cancellationToken = AICancellationToken();

    final execution = harness.orchestrator.execute(
      _request('cancelled'),
      cancellationToken: cancellationToken,
    );
    await provider.started.future;
    cancellationToken.cancel();

    await expectLater(
      execution,
      throwsA(
        isA<AIEngineException>().having(
          (error) => error.error.code,
          'code',
          AIErrorCode.cancelled,
        ),
      ),
    );

    expect(states.last, SystemCoreProcessStatus.cancelled);
    final record = (await harness.repository.getAll()).single;
    expect(record.status, SystemCoreProcessStatus.cancelled);
    expect(record.finishedAt, isNotNull);
  });

  test('records engine timeout as a distinct terminal state', () async {
    final provider = _FakeProvider(waitForCancellation: true);
    final harness = _OrchestratorHarness(
      provider: provider,
      timeout: const Duration(milliseconds: 10),
    );
    addTearDown(harness.dispose);
    final states = harness.watchProcessStates();

    await expectLater(
      harness.orchestrator.execute(_request('timeout')),
      throwsA(
        isA<AIEngineException>().having(
          (error) => error.error.code,
          'code',
          AIErrorCode.timeout,
        ),
      ),
    );

    expect(states.last, SystemCoreProcessStatus.timeout);
    final record = (await harness.repository.getAll()).single;
    expect(record.status, SystemCoreProcessStatus.timeout);
    expect(record.errorMessage, contains('timed out'));
    expect(record.finishedAt, isNotNull);
  });
}

AIRequest _request(String id) => AIRequest(
  id: id,
  prompt: 'test prompt',
  metadata: const {'source': 'unit-test'},
);

class _OrchestratorHarness {
  _OrchestratorHarness({
    required AIProvider provider,
    Duration timeout = const Duration(seconds: 1),
  }) {
    var now = DateTime.utc(2026, 10, 8);
    DateTime clock() {
      final current = now;
      now = now.add(const Duration(seconds: 1));
      return current;
    }

    processService = SystemCoreProcessService(clock: clock);
    orchestrator = AIProcessOrchestrator(
      engine: AIEngine(provider: provider, timeout: timeout),
      processService: processService,
      historyRepository: repository,
      runIdFactory: () => 'run-${_nextId++}',
    );
  }

  final repository = InMemoryRunHistoryRepository();
  late final SystemCoreProcessService processService;
  late final AIProcessOrchestrator orchestrator;
  int _nextId = 1;

  List<SystemCoreProcessStatus> watchProcessStates() {
    final statuses = <SystemCoreProcessStatus>[];
    processService.states.listen((state) {
      if (statuses.isEmpty || statuses.last != state.status) {
        statuses.add(state.status);
      }
    });
    return statuses;
  }

  Future<void> dispose() async {
    await orchestrator.dispose();
    await processService.dispose();
    await repository.dispose();
  }
}

class _FakeProvider implements AIProvider {
  _FakeProvider({this.error, this.waitForCancellation = false});

  final Object? error;
  final bool waitForCancellation;
  final Completer<void> started = Completer<void>();

  @override
  String get id => 'fake';

  @override
  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  }) async {
    if (!started.isCompleted) started.complete();
    if (error != null) throw error!;
    if (waitForCancellation) await cancellationToken.cancelled;
    return AIResponse(
      requestId: request.id,
      text: 'generated response',
      providerId: id,
      generatedAt: DateTime.utc(2026, 10, 8),
    );
  }
}
