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
import 'package:omni_ai/features/news/services/news_rss_service.dart';
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

  testWidgets('fetches fresh personalized RSS articles for news questions', (
    WidgetTester tester,
  ) async {
    var requestCount = 0;
    final service = NewsRssService(
      client: MockClient((request) async {
        requestCount++;
        expect(request.url.host, 'news.google.com');
        return http.Response(
          '<rss><channel><item>'
          '<title>Live anime announcement</title>'
          '<link>https://publisher.example/live-anime</link>'
          '<description>A newly fetched anime update.</description>'
          '<pubDate>Wed, 14 Oct 2026 10:00:00 GMT</pubDate>'
          '<source>Live Anime News</source>'
          '</item></channel></rss>',
          200,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        );
      }),
    );
    addTearDown(service.dispose);

    final submittedPrompt = await _sendPrompt(
      tester,
      'Какие последние новости по аниме?',
      newsService: service,
      saveAnimeInterest: true,
    );

    expect(requestCount, 3);
    expect(submittedPrompt, contains('Live anime announcement'));
    expect(submittedPrompt, contains('Saved anime announcement'));
    expect(submittedPrompt, contains('свежие RSS-кандидаты'));
    expect(submittedPrompt, contains('https://publisher.example/live-anime'));
  });

  testWidgets('fetches discovery RSS articles without saved interests', (
    WidgetTester tester,
  ) async {
    var requestCount = 0;
    final service = NewsRssService(
      client: MockClient((request) async {
        requestCount++;
        expect(request.url.host, 'news.google.com');
        return http.Response(
          '<rss><channel><item>'
          '<title>Global discovery headline</title>'
          '<link>https://publisher.example/global-discovery</link>'
          '<description>A general world news update.</description>'
          '<pubDate>Wed, 14 Oct 2026 10:00:00 GMT</pubDate>'
          '<source>World News</source>'
          '</item></channel></rss>',
          200,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        );
      }),
    );
    addTearDown(service.dispose);

    final submittedPrompt = await _sendPrompt(
      tester,
      'Какие последние новости в мире?',
      newsService: service,
    );

    expect(requestCount, 3);
    expect(submittedPrompt, contains('Global discovery headline'));
    expect(submittedPrompt, contains('свежие RSS-кандидаты'));
    expect(
      submittedPrompt,
      contains('https://publisher.example/global-discovery'),
    );
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

Future<String> _sendPrompt(
  WidgetTester tester,
  String prompt, {
  NewsRssService? newsService,
  bool saveAnimeInterest = false,
}) async {
  _checkpoint('[news-context-test] helper entered');
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

  if (saveAnimeInterest) {
    await preferences.setString(
      'omni_ai.news_interest_profile.v1',
      jsonEncode({
        'topics': ['anime'],
        'languages': ['ru'],
        'regions': [],
        'includeCriticalOutsideInterests': false,
      }),
    );
  }

  _checkpoint('[news-context-test] cached news written');
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

  _checkpoint('[news-context-test] dependencies composed');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
          body: AIChatPage(
            dependencies: dependencies,
            newsService: newsService,
          ),
        ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  _checkpoint('[news-context-test] initial widget pumps complete');
  await tester.enterText(find.byType(TextField), prompt);
  _checkpoint('[news-context-test] prompt entered');
  await tester.tap(find.byTooltip('Отправить'));
  _checkpoint('[news-context-test] send tapped');
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  _checkpoint('[news-context-test] send pumps complete; submittedPrompt=${submittedPrompt != null}');
  expect(submittedPrompt, isNotNull);
  expect(
    submittedPrompt,
    isNotEmpty,
    reason: 'The mock provider must receive the submitted prompt.',
  );
  expect(tester.takeException(), isNull);

  _checkpoint('[news-context-test] beginning widget teardown');
  await tester.pumpWidget(const SizedBox.shrink());
  _checkpoint('[news-context-test] widget teardown complete');
  // Dispose resources through the composition root. The injected process
  // service remains caller-owned and is closed after the recorder drains.
  await tester.pump();
  _checkpoint('[news-context-test] disposing dependencies outside fake async');
  await tester.runAsync(
    () => dependencies.dispose().timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('Dependency disposal timed out.'),
    ),
  );
  _checkpoint('[news-context-test] dependencies disposed');
  await tester.runAsync(
    () => dependencies.processService.dispose().timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw TimeoutException('Process service disposal timed out.'),
    ),
  );
  _checkpoint('[news-context-test] process service disposed');
  _checkpoint('[news-context-test] helper complete');
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

void _checkpoint(String message) {
  // ignore: avoid_print
  print(message);
}
