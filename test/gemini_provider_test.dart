import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/core/ai_engine/models/ai_error.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:omni_ai/providers/gemini/gemini_api_config.dart';
import 'package:omni_ai/providers/gemini/gemini_api_key_source.dart';
import 'package:omni_ai/providers/gemini/gemini_provider.dart';

void main() {
  group('GeminiProvider', () {
    test('maps successful Interactions API response to AIResponse', () async {
      http.Request? capturedRequest;
      final provider = _provider((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'id': 'interaction-123',
            'outputs': [
              {'type': 'text', 'text': 'Hello '},
              {'type': 'text', 'text': 'from Gemini'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }, apiKeySource: const EnvironmentGeminiApiKeySource(
        apiKey: 'local-test-key',
      ));
      addTearDown(provider.close);

      final result = await _engine(provider).execute(_request());

      expect(capturedRequest?.method, 'POST');
      expect(capturedRequest?.url, Uri.parse(GeminiApiConfig().endpoint));
      expect(capturedRequest?.headers['x-goog-api-key'], 'local-test-key');
      expect(jsonDecode(capturedRequest!.body), {
        'model': 'gemini-3.8-flash',
        'input': 'Say hello',
        'store': false,
      });
      expect(result.requestId, 'request-1');
      expect(result.text, 'Hello from Gemini');
      expect(result.providerId, 'gemini');
      expect(result.metadata, {
        'model': 'gemini-3.8-flash',
        'interactionId': 'interaction-123',
      });
      expect(result.generatedAt, isA<DateTime>());
    });

    test('reports a clear error when the API key is missing', () async {
      var requestSent = false;
      final provider = _provider((_) async {
        requestSent = true;
        return http.Response('', 200);
      }, apiKeySource: _FakeApiKeySource(null));
      addTearDown(provider.close);

      await expectLater(
        _engine(provider).execute(_request()),
        throwsA(
          isA<AIEngineException>()
              .having(
                (error) => error.error.code,
                'code',
                AIErrorCode.invalidRequest,
              )
              .having(
                (error) => error.error.message,
                'message',
                contains('Gemini API key is not configured'),
              ),
        ),
      );
      expect(requestSent, isFalse);
    });

    test('reads and trims the configured development environment key', () async {
      const source = EnvironmentGeminiApiKeySource(apiKey: ' local-test-key ');

      expect(await source.readApiKey(), 'local-test-key');
      expect(
        await const EnvironmentGeminiApiKeySource(apiKey: '').readApiKey(),
        isNull,
      );
    });

    test('maps Gemini API errors to AIEngine provider errors', () async {
      final provider = _provider(
        (_) async =>
            http.Response('{"error":{"message":"quota exceeded"}}', 429),
      );
      addTearDown(provider.close);

      await expectLater(
        _engine(provider).execute(_request()),
        throwsA(
          isA<AIEngineException>()
              .having((error) => error.error.code, 'code', AIErrorCode.provider)
              .having((error) => error.error.retryable, 'retryable', isTrue)
              .having(
                (error) => error.error.message,
                'message',
                contains('quota exceeded'),
              ),
        ),
      );
    });

    test('maps malformed and empty outputs to provider errors', () async {
      final malformedProvider = _provider(
        (_) async => http.Response('not-json', 200),
      );
      addTearDown(malformedProvider.close);
      await expectLater(
        _engine(malformedProvider).execute(_request()),
        throwsA(
          isA<AIEngineException>().having(
            (error) => error.error.code,
            'code',
            AIErrorCode.provider,
          ),
        ),
      );

      final emptyProvider = _provider(
        (_) async => http.Response('{"outputs":[]}', 200),
      );
      addTearDown(emptyProvider.close);
      await expectLater(
        _engine(emptyProvider).execute(_request()),
        throwsA(
          isA<AIEngineException>()
              .having((error) => error.error.code, 'code', AIErrorCode.provider)
              .having(
                (error) => error.error.message,
                'message',
                contains('no text output'),
              ),
        ),
      );
    });

    test('sends system instruction in the Interactions API request', () async {
      http.Request? capturedRequest;
      final provider = _provider((request) async {
        capturedRequest = request;
        return http.Response('{"outputs":[{"type":"text","text":"ok"}]}', 200);
      });
      addTearDown(provider.close);

      await _engine(
        provider,
      ).execute(_request().copyWith(systemInstruction: 'Respond in Russian.'));

      expect(
        jsonDecode(capturedRequest!.body)['system_instruction'],
        'Respond in Russian.',
      );
    });

    test('has a stable provider id', () {
      final first = _provider((_) async => http.Response('', 200));
      final second = _provider((_) async => http.Response('', 200));
      addTearDown(first.close);
      addTearDown(second.close);

      expect(first.id, 'gemini');
      expect(second.id, first.id);
    });

    test(
      'uses the AIEngine cancellation token to abort HTTP transport',
      () async {
        final requestSent = Completer<http.BaseRequest>();
        final response = Completer<http.StreamedResponse>();
        final client = _CapturingClient((request) {
          requestSent.complete(request);
          return response.future;
        });
        final provider = GeminiProvider(
          apiKeySource: _FakeApiKeySource(),
          client: client,
        );
        addTearDown(provider.close);
        final cancellationToken = AICancellationToken();

        final execution = _engine(
          provider,
        ).execute(_request(), cancellationToken: cancellationToken);
        final request = await requestSent.future;
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
        expect(request, isA<http.AbortableRequest>());
        expect(
          (request as http.AbortableRequest).abortTrigger,
          same(cancellationToken.cancelled),
        );

        response.complete(
          http.StreamedResponse(
            Stream.value(
              utf8.encode('{"outputs":[{"type":"text","text":"late"}]}'),
            ),
            200,
          ),
        );
      },
    );
  });
}

AIRequest _request() => const AIRequest(id: 'request-1', prompt: 'Say hello');

AIEngine _engine(AIProvider provider) =>
    AIEngine(provider: provider, timeout: const Duration(seconds: 1));

GeminiProvider _provider(
  Future<http.Response> Function(http.Request) handler, {
  GeminiApiConfig config = const GeminiApiConfig(),
  GeminiApiKeySource? apiKeySource,
}) => GeminiProvider(
  apiKeySource: apiKeySource ?? _FakeApiKeySource(),
  config: config,
  client: MockClient(handler),
);

class _FakeApiKeySource implements GeminiApiKeySource {
  _FakeApiKeySource([this.apiKey = 'test-only-key']);

  final String? apiKey;

  @override
  Future<String?> readApiKey() async => apiKey;
}

class _CapturingClient extends http.BaseClient {
  _CapturingClient(this._send);

  final Future<http.StreamedResponse> Function(http.BaseRequest) _send;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _send(request);

  @override
  void close() {}
}
