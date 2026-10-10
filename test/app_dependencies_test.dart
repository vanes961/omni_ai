import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_execution_mode_store.dart';
import 'package:omni_ai/core/ai_engine/providers/routing_ai_provider.dart';
import 'package:omni_ai/core/di/app_dependencies.dart';
import 'package:omni_ai/features/run_history/data/in_memory_run_history_repository.dart';
import 'package:omni_ai/features/system_core/services/system_core_process_service.dart';
import 'package:omni_ai/providers/openrouter/openrouter_api_key_source.dart';

void main() {
  test('composes OpenRouter execution and persists the completed run', () async {
    final repository = InMemoryRunHistoryRepository();
    final processService = SystemCoreProcessService();
    final dependencies = AppDependencies(
      apiKeySource: const _TestApiKeySource(),
      aiExecutionModeStore: _TestExecutionModeStore(),
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.headers['authorization'], 'Bearer test-key');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['messages'].last['content'], 'Remember that I prefer concise answers.');
        return http.Response(
          jsonEncode({
            'id': 'chatcmpl-1',
            'model': 'openrouter/free',
            'choices': [
              {'message': {'role': 'assistant', 'content': 'Understood — I will be concise.'}},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      processService: processService,
      runHistoryRepository: repository,
    );
    addTearDown(dependencies.dispose);

    final response = await dependencies.orchestrator.execute(
      AIRequest(id: 'request-1', prompt: 'Remember that I prefer concise answers.'),
    );

    expect(response.text, 'Understood — I will be concise.');
    expect(response.providerId, 'openrouter');
    final records = await repository.getAll();
    expect(records, hasLength(1));
    expect(records.single.status.name, 'completed');
    expect(
      records.single.logEntries.map((entry) => entry.message),
      containsAll(['AI REQUEST request-1', 'AI PROVIDER openrouter']),
    );
  });
}

class _TestApiKeySource implements OpenRouterApiKeySource {
  const _TestApiKeySource();
  @override
  Future<String?> readApiKey() async => 'test-key';
}

class _TestExecutionModeStore implements AIExecutionModeStore {
  @override
  Future<AIExecutionMode> load() async => AIExecutionMode.cloud;
  @override
  Future<void> save(AIExecutionMode mode) async {}
}
