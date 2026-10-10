import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/models/ai_error.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
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

    test('defaults to local and never invokes cloud', () async {
      final response = await router.complete(
        _request,
        cancellationToken: AICancellationToken(),
      );

      expect(response.providerId, 'local');
      expect(local.calls, 1);
      expect(cloud.calls, 0);
    });

    test('uses cloud only after explicit mode selection', () async {
      router.mode = AIExecutionMode.cloud;

      final response = await router.complete(
        _request,
        cancellationToken: AICancellationToken(),
      );

      expect(response.providerId, 'cloud');
      expect(local.calls, 0);
      expect(cloud.calls, 1);
    });

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
