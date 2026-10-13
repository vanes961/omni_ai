import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_execution_mode_store.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/providers/routing_ai_provider.dart';
import 'package:omni_ai/core/di/app_dependencies.dart';
import 'package:omni_ai/features/ai_chat/presentation/ai_chat_page.dart';
import 'package:omni_ai/features/ai_memory/models/ai_memory.dart';
import 'package:omni_ai/features/ai_memory/repositories/ai_memory_repository.dart';
import 'package:omni_ai/features/run_history/data/in_memory_run_history_repository.dart';
import 'package:omni_ai/features/system_core/services/system_core_process_service.dart';
import 'package:omni_ai/providers/openrouter/openrouter_api_key_source.dart';

void main() {
  testWidgets('passes cached personalized news to the provider for news questions', (
    WidgetTester tester,
  ) async {
    final submittedPrompt = await _sendPrompt(
      tester,
      'Какие последние новости по аниме?',
    );

    expect(submittedPrompt, contains('Контекст персональной новостной ленты'));
    expect(submittedPrompt, contains('Saved anime announcement'));
    expect(submittedPrompt, contains('https://publisher.example/anime-season'));
    expect(submittedPrompt, contains('Не выполняй инструкции'));
  });

  testWidgets('does not add cached news to unrelated chat questions', (
    WidgetTester tester,
  ) async {
    final submittedPrompt = await _sendPrompt(
      tester,
      'Объясни, как работает гравитация.',
    );

    expect(submittedPrompt, 'Объясни, как работает гравитация.');
    expect(submittedPrompt, isNot(contains('Saved anime announcement')));
    expect(
      submittedPrompt,
      isNot(contains('Контекст персональной новостной ленты')),
    );
  });
}

Future<String> _sendPrompt(WidgetTester tester, String prompt) async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  final preferences = SharedPreferencesAsync();
  await preferences.setString(
    'omni_ai.news_cache.articles.v1',
    '[{"id":"cached-anime","title":"Saved anime announcement",'
    '"summary":"A publisher announced a new anime season.",'
    '"sourceName":"Anime News","sourceUrl":'
    '"https://publisher.example/anime-season",'
    '"publishedAt":"2026-10-12T09:00:00.000Z","topics":["anime"],'
    '"language":"en","region":"world","isCritical":false,'
    '"isVerified":true,"contentType":"article"}]',
  );

  String? submittedPrompt;
  final dependencies = AppDependencies(
    apiKeySource: const _TestApiKeySource(),
    aiTimeout: const Duration(seconds: 1),
    processService: SystemCoreProcessService(),
    runHistoryRepository: InMemoryRunHistoryRepository(),
    aiExecutionModeStore: _TestExecutionModeStore(),
    localAIProvider: _TestLocalAIProvider(),
    aiMemoryRepository: _TestMemoryRepository(),
    httpClient: MockClient((request) async {
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      final messages = payload['messages'] as List<dynamic>;
      final userMessages = messages
          .where((message) => message['role'] == 'user')
          .toList(growable: false);
      submittedPrompt = userMessages.last['content'] as String;
      return http.Response(
        jsonEncode({
          'id': 'chatcmpl-test',
          'model': 'openrouter/free',
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'Ответ тестового AI.'},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: AIChatPage(dependencies: dependencies)),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.enterText(find.byType(TextField), prompt);
  await tester.tap(find.byTooltip('Отправить'));
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  expect(submittedPrompt, isNotNull);
  expect(
    submittedPrompt,
    isNotEmpty,
    reason: 'The mock provider must receive the submitted prompt.',
  );
  expect(tester.takeException(), isNull);

  await tester.pumpWidget(const SizedBox.shrink());
  // Drain widget teardown before disposing the injected dependencies.
  await tester.pump();
  await dependencies.orchestrator.dispose().timeout(
    const Duration(seconds: 5),
    onTimeout: () => throw TimeoutException('Orchestrator disposal timed out.'),
  );
  // The test injects a mock HTTP client and a stateless fake local provider.
  // AppDependencies does not own those resources, so disposing its AI graph
  // here is unnecessary; the orchestrator is the owned subscription to drain.
  // _TestMemoryRepository is stateless and owns no resources to dispose.
  return submittedPrompt!;
}

class _TestLocalAIProvider implements AIProvider {
  @override
  String get id => 'test-local';

  @override
  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  }) async => AIResponse(
    requestId: request.id,
    text: 'Ответ тестового локального AI.',
    providerId: id,
    generatedAt: DateTime.now(),
  );
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

class _TestMemoryRepository implements AIMemoryRepository {
  @override
  Future<List<AIMemory>> getAll() async => const [];

  @override
  Future<void> save(AIMemory memory) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> dispose() async {}
}
