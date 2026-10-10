import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/models/ai_error.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_execution_mode_store.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/providers/routing_ai_provider.dart';
import 'package:omni_ai/core/di/ai_dependencies.dart';

void main() {
  group('AIDependencies', () {
    late _MemoryModeStore modeStore;
    late _FakeProvider localProvider;
    late AIDependencies dependencies;

    setUp(() {
      modeStore = _MemoryModeStore();
      localProvider = _FakeProvider('local');
      dependencies = AIDependencies(
        localProvider: localProvider,
        modeStore: modeStore,
      );
    });

    tearDown(() async {
      await dependencies.dispose();
    });

    test('restores local as the default before the first request', () async {
      final response = await dependencies.engine.execute(_request);

      expect(response.providerId, 'local');
      expect(dependencies.executionMode, AIExecutionMode.local);
      expect(modeStore.loadCalls, 1);
      expect(localProvider.calls, 1);
    });

    test('restores saved cloud mode before routing a request', () async {
      modeStore.storedMode = AIExecutionMode.cloud;

      await expectLater(
        dependencies.engine.execute(_request),
        throwsA(
          isA<AIEngineException>().having(
            (error) => error.error.message,
            'message',
            'OpenRouter API key is not configured.',
          ),
        ),
      );

      expect(dependencies.executionMode, AIExecutionMode.cloud);
      expect(localProvider.calls, 0);
      expect(modeStore.loadCalls, 1);
    });

    test('persists explicit mode changes', () async {
      await dependencies.setExecutionMode(AIExecutionMode.cloud);

      expect(dependencies.executionMode, AIExecutionMode.cloud);
      expect(modeStore.savedMode, AIExecutionMode.cloud);
    });

    test('reverts the route if persisting a mode fails', () async {
      modeStore.failSave = true;

      await expectLater(
        dependencies.setExecutionMode(AIExecutionMode.cloud),
        throwsA(isA<StateError>()),
      );

      expect(dependencies.executionMode, AIExecutionMode.local);
    });
  });
}

final _request = AIRequest(id: 'dependencies-test', prompt: 'Hello');

class _MemoryModeStore implements AIExecutionModeStore {
  AIExecutionMode? storedMode;
  AIExecutionMode? savedMode;
  int loadCalls = 0;
  bool failSave = false;

  @override
  Future<AIExecutionMode> load() async {
    loadCalls++;
    return storedMode ?? AIExecutionMode.local;
  }

  @override
  Future<void> save(AIExecutionMode mode) async {
    if (failSave) throw StateError('Unable to persist mode.');
    storedMode = mode;
    savedMode = mode;
  }
}

class _FakeProvider implements AIProvider {
  _FakeProvider(this.id);

  @override
  final String id;
  int calls = 0;

  @override
  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  }) async {
    calls++;
    return AIResponse(
      requestId: request.id,
      text: 'local response',
      providerId: id,
      generatedAt: DateTime.utc(2026),
    );
  }
}
