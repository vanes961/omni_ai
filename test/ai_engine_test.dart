import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/models/ai_error.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_streaming_provider.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';

void main() {
  group('AIEngine', () {
    test('returns provider response', () async {
      final engine = AIEngine(
        provider: _FakeProvider(responseText: 'Привет из AI Engine.'),
      );

      final response = await engine.execute(
        const AIRequest(id: 'request-1', prompt: 'Привет'),
      );

      expect(response.requestId, 'request-1');
      expect(response.text, 'Привет из AI Engine.');
      expect(response.providerId, 'fake');
    });

    test('rejects empty prompt before provider call', () async {
      final provider = _FakeProvider();
      final engine = AIEngine(provider: provider);

      await expectLater(
        engine.execute(const AIRequest(id: 'request-2', prompt: '   ')),
        throwsA(
          isA<AIEngineException>().having(
            (error) => error.error.code,
            'code',
            AIErrorCode.invalidRequest,
          ),
        ),
      );
      expect(provider.callCount, 0);
    });

    test('maps provider failure to a retryable provider error', () async {
      final engine = AIEngine(
        provider: _FakeProvider(error: StateError('provider unavailable')),
      );

      await expectLater(
        engine.execute(const AIRequest(id: 'request-3', prompt: 'Тест')),
        throwsA(
          isA<AIEngineException>()
              .having((error) => error.error.code, 'code', AIErrorCode.provider)
              .having((error) => error.error.retryable, 'retryable', isTrue),
        ),
      );
    });

    test('supports cooperative cancellation', () async {
      final token = AICancellationToken();
      final provider = _FakeProvider(waitForCancellation: true);
      final engine = AIEngine(
        provider: provider,
        timeout: const Duration(seconds: 1),
      );

      final future = engine.execute(
        const AIRequest(id: 'request-4', prompt: 'Долгая задача'),
        cancellationToken: token,
      );

      token.cancel();

      await expectLater(
        future,
        throwsA(
          isA<AIEngineException>().having(
            (error) => error.error.code,
            'code',
            AIErrorCode.cancelled,
          ),
        ),
      );
    });

    test('does not forward streamed chunks after cancellation', () async {
      final provider = _FakeStreamingProvider();
      final engine = AIEngine(provider: provider);
      final token = AICancellationToken();
      final received = <String>[];

      final future = engine.execute(
        const AIRequest(id: 'request-stream-cancel', prompt: 'Стрим'),
        cancellationToken: token,
        onToken: received.add,
      );
      await provider.started.future;
      token.cancel();

      await expectLater(
        future,
        throwsA(
          isA<AIEngineException>().having(
            (error) => error.error.code,
            'code',
            AIErrorCode.cancelled,
          ),
        ),
      );
      provider.releaseLateChunk.complete();
      await Future<void>.delayed(Duration.zero);

      expect(received, ['first']);
    });

    test('times out and requests provider cancellation', () async {
      final provider = _FakeProvider(waitForCancellation: true);
      final engine = AIEngine(
        provider: provider,
        timeout: const Duration(milliseconds: 20),
      );
      final token = AICancellationToken();

      final future = engine.execute(
        const AIRequest(id: 'request-5', prompt: 'Зависшая задача'),
        cancellationToken: token,
      );

      await expectLater(
        future,
        throwsA(
          isA<AIEngineException>().having(
            (error) => error.error.code,
            'code',
            AIErrorCode.timeout,
          ),
        ),
      );
      expect(token.isCancelled, isTrue);
    });

    test('times out during setup before calling the provider', () async {
      final setup = Completer<void>();
      final provider = _FakeProvider();
      final token = AICancellationToken();
      final engine = AIEngine(
        provider: provider,
        timeout: const Duration(milliseconds: 20),
        beforeExecute: () => setup.future,
      );

      await expectLater(
        engine.execute(
          const AIRequest(id: 'request-6', prompt: 'Загрузка модели'),
          cancellationToken: token,
        ),
        throwsA(
          isA<AIEngineException>().having(
            (error) => error.error.code,
            'code',
            AIErrorCode.timeout,
          ),
        ),
      );

      expect(token.isCancelled, isTrue);
      setup.complete();
      await Future<void>.delayed(Duration.zero);
      expect(provider.callCount, 0);
    });
  });
}

class _FakeProvider implements AIProvider {
  _FakeProvider({
    this.responseText = 'ok',
    this.error,
    this.waitForCancellation = false,
  });

  final String responseText;
  final Object? error;
  final bool waitForCancellation;

  int callCount = 0;

  @override
  String get id => 'fake';

  @override
  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  }) async {
    callCount++;
    if (error != null) throw error!;

    if (waitForCancellation) {
      await cancellationToken.cancelled;
    }

    return AIResponse(
      requestId: request.id,
      text: responseText,
      providerId: id,
      generatedAt: DateTime.utc(2026, 1, 1),
    );
  }
}

class _FakeStreamingProvider implements AIProvider, AIStreamingProvider {
  final started = Completer<void>();
  final releaseLateChunk = Completer<void>();

  @override
  String get id => 'fake-streaming';

  @override
  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  }) => throw UnimplementedError();

  @override
  Future<AIResponse> completeStreaming(
    AIRequest request, {
    required AICancellationToken cancellationToken,
    required void Function(String token) onToken,
  }) async {
    onToken('first');
    if (!started.isCompleted) started.complete();
    await releaseLateChunk.future;
    onToken('late');
    return AIResponse(
      requestId: request.id,
      text: 'firstlate',
      providerId: id,
      generatedAt: DateTime.utc(2026, 10, 16),
    );
  }
}
