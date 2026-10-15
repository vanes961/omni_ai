import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/models/ai_error.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_streaming_provider.dart';
import 'package:omni_ai/core/ai_engine/providers/routing_ai_provider.dart';

void main() {
  group('RoutingAIProvider', () {
    late _FakeProvider local;
    late _FakeProvider cloud;
    late RoutingAIProvider router;

    setUp(() {
      local = _FakeProvider('local');
      cloud = _FakeProvider('cloud');
      router = RoutingAIProvider(localProvider: local, cloudProvider: cloud);
    });

    test('defaults to automatic and keeps greetings local', () async {
      final response = await router.complete(
        _request,
        cancellationToken: AICancellationToken(),
      );

      expect(response.providerId, 'local');
      expect(local.calls, 1);
      expect(cloud.calls, 0);
    });

    test('routes ordinary questions to local in automatic mode', () async {
      final response = await router.complete(
        AIRequest(id: 'general-question', prompt: 'Почему небо голубое?'),
        cancellationToken: AICancellationToken(),
      );

      expect(response.providerId, 'local');
      expect(local.calls, 1);
      expect(cloud.calls, 0);
    });

    test(
      'routes writing and recommendations to local in automatic mode',
      () async {
        final response = await router.complete(
          AIRequest(
            id: 'writing-request',
            prompt: 'Посоветуй фильм с неожиданной концовкой',
          ),
          cancellationToken: AICancellationToken(),
        );

        expect(response.providerId, 'local');
        expect(local.calls, 1);
        expect(cloud.calls, 0);
      },
    );

    test('keeps conversational uses of current-time words local', () async {
      final response = await router.complete(
        AIRequest(
          id: 'scene-question',
          prompt: 'Объясни, что сейчас происходит в этой сцене',
        ),
        cancellationToken: AICancellationToken(),
      );

      expect(response.providerId, 'local');
      expect(local.calls, 1);
      expect(cloud.calls, 0);
    });

    test(
      'keeps writing a news item local when no current facts are requested',
      () async {
        final response = await router.complete(
          AIRequest(
            id: 'write-news-item',
            prompt: 'Помоги написать новость о школьном мероприятии',
          ),
          cancellationToken: AICancellationToken(),
        );

        expect(response.providerId, 'local');
        expect(local.calls, 1);
        expect(cloud.calls, 0);
      },
    );

    test('routes explicit current-news requests to cloud', () async {
      final response = await router.complete(
        AIRequest(id: 'current-news', prompt: 'Какие новости сегодня?'),
        cancellationToken: AICancellationToken(),
      );

      expect(response.providerId, 'cloud');
      expect(local.calls, 0);
      expect(cloud.calls, 1);
    });

    test('routes explicit internet searches to cloud', () async {
      final response = await router.complete(
        AIRequest(
          id: 'web-search',
          prompt: 'Проверь в интернете последние данные о запуске миссии',
        ),
        cancellationToken: AICancellationToken(),
      );

      expect(response.providerId, 'cloud');
      expect(local.calls, 0);
      expect(cloud.calls, 1);
    });

    test('uses local when local mode is explicitly selected', () async {
      router.mode = AIExecutionMode.local;

      final response = await router.complete(
        AIRequest(id: 'forced-local', prompt: 'Какие новости сегодня?'),
        cancellationToken: AICancellationToken(),
      );

      expect(response.providerId, 'local');
      expect(local.calls, 1);
      expect(cloud.calls, 0);
    });

    test('uses cloud when cloud mode is explicitly selected', () async {
      router.mode = AIExecutionMode.cloud;

      final response = await router.complete(
        _request,
        cancellationToken: AICancellationToken(),
      );

      expect(response.providerId, 'cloud');
      expect(local.calls, 0);
      expect(cloud.calls, 1);
    });

    test('falls back to local when automatic cloud request fails', () async {
      cloud.failure = StateError('network unavailable');

      final response = await router.complete(
        AIRequest(id: 'news-offline', prompt: 'Какие новости сегодня?'),
        cancellationToken: AICancellationToken(),
      );

      expect(response.providerId, 'local');
      expect(cloud.calls, 1);
      expect(local.calls, 1);
    });

    test(
      'falls back to local streaming before any cloud token is emitted',
      () async {
        cloud.failure = StateError('network unavailable');
        final tokens = <String>[];

        final response = await router.completeStreaming(
          AIRequest(id: 'stream-offline', prompt: 'Какие новости сегодня?'),
          cancellationToken: AICancellationToken(),
          onToken: tokens.add,
        );

        expect(response.providerId, 'local');
        expect(tokens, ['reply from local']);
        expect(cloud.calls, 1);
        expect(local.calls, 1);
      },
    );

    test(
      'does not append local output after partial cloud streaming output',
      () async {
        final streamingCloud = _FakeStreamingProvider('cloud')
          ..failure = StateError('connection dropped')
          ..emitBeforeFailure = true;
        final streamingRouter = RoutingAIProvider(
          localProvider: local,
          cloudProvider: streamingCloud,
        );
        final tokens = <String>[];

        await expectLater(
          streamingRouter.completeStreaming(
            AIRequest(id: 'stream-partial', prompt: 'Какие новости сегодня?'),
            cancellationToken: AICancellationToken(),
            onToken: tokens.add,
          ),
          throwsA(isA<StateError>()),
        );

        expect(tokens, ['partial cloud answer']);
        expect(local.calls, 0);
        expect(streamingCloud.calls, 1);
      },
    );

    test('does not fall back when selected local provider fails', () async {
      local.failure = StateError('local model unavailable');

      await expectLater(
        router.complete(_request, cancellationToken: AICancellationToken()),
        throwsA(isA<StateError>()),
      );

      expect(local.calls, 1);
      expect(cloud.calls, 0);
    });

    test(
      'rejects already-cancelled requests before invoking providers',
      () async {
        final token = AICancellationToken()..cancel();

        await expectLater(
          router.complete(_request, cancellationToken: token),
          throwsA(
            isA<AIEngineException>().having(
              (error) => error.error.code,
              'error code',
              AIErrorCode.cancelled,
            ),
          ),
        );

        expect(local.calls, 0);
        expect(cloud.calls, 0);
      },
    );
  });
}

final _request = AIRequest(id: 'test-request', prompt: 'Hello');

class _FakeProvider implements AIProvider {
  _FakeProvider(this.id);

  @override
  final String id;
  int calls = 0;
  Object? failure;

  @override
  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  }) async {
    calls++;
    final error = failure;
    if (error != null) throw error;
    return AIResponse(
      requestId: request.id,
      text: 'reply from $id',
      providerId: id,
      generatedAt: DateTime.utc(2026),
    );
  }
}

class _FakeStreamingProvider extends _FakeProvider
    implements AIStreamingProvider {
  _FakeStreamingProvider(super.id);

  bool emitBeforeFailure = false;

  @override
  Future<AIResponse> completeStreaming(
    AIRequest request, {
    required AICancellationToken cancellationToken,
    required void Function(String token) onToken,
  }) async {
    calls++;
    if (emitBeforeFailure) onToken('partial cloud answer');
    final error = failure;
    if (error != null) throw error;
    final response = AIResponse(
      requestId: request.id,
      text: 'reply from $id',
      providerId: id,
      generatedAt: DateTime.utc(2026),
    );
    if (response.text.isNotEmpty) onToken(response.text);
    return response;
  }
}
