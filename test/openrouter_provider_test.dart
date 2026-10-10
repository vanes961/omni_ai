import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/core/ai_engine/models/ai_error.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:omni_ai/providers/openrouter/openrouter_api_config.dart';
import 'package:omni_ai/providers/openrouter/openrouter_api_key_source.dart';
import 'package:omni_ai/providers/openrouter/openrouter_provider.dart';

void main() {
  test('sends OpenAI-compatible chat completion and maps the response', () async {
    http.Request? captured;
    final provider = _provider((request) async {
      captured = request;
      return http.Response(jsonEncode({
        'id': 'chatcmpl-test',
        'model': 'free-model/test',
        'choices': [{'message': {'role': 'assistant', 'content': 'Привет!'}}],
      }), 200, headers: {'content-type': 'application/json'});
    });
    addTearDown(provider.close);
    final result = await _engine(provider).execute(_request());
    expect(captured!.url, Uri.parse(OpenRouterApiConfig().endpoint));
    expect(captured!.headers['authorization'], 'Bearer test-key');
    expect(jsonDecode(captured!.body), {
      'model': 'openrouter/free',
      'messages': [{'role': 'user', 'content': 'Say hello'}],
      'stream': false,
    });
    expect(result.text, 'Привет!');
    expect(result.providerId, 'openrouter');
    expect(result.metadata['model'], 'free-model/test');
    expect(result.metadata['responseId'], 'chatcmpl-test');
  });

  test('includes optional system instruction', () async {
    http.Request? captured;
    final provider = _provider((request) async {
      captured = request;
      return http.Response('{"choices":[{"message":{"content":"ok"}}]}', 200);
    });
    addTearDown(provider.close);
    await _engine(provider).execute(_request().copyWith(systemInstruction: 'Answer in Russian.'));
    expect(jsonDecode(captured!.body)['messages'].first, {
      'role': 'system', 'content': 'Answer in Russian.',
    });
  });

  test('does not send a request without a key', () async {
    var sent = false;
    final provider = _provider((_) async {
      sent = true;
      return http.Response('{}', 200);
    }, apiKeySource: _FakeKeySource(null));
    addTearDown(provider.close);
    await expectLater(
      _engine(provider).execute(_request()),
      throwsA(isA<AIEngineException>().having(
        (e) => e.error.message, 'message', contains('OpenRouter API key is not configured'),
      )),
    );
    expect(sent, isFalse);
  });

  test('maps rate limits and API errors', () async {
    final provider = _provider((_) async =>
      http.Response('{"error":{"message":"free quota exceeded"}}', 429));
    addTearDown(provider.close);
    await expectLater(
      _engine(provider).execute(_request()),
      throwsA(isA<AIEngineException>()
        .having((e) => e.error.retryable, 'retryable', isTrue)
        .having((e) => e.error.message, 'message', contains('free quota exceeded'))),
    );
  });

  test('rejects malformed or empty completion content', () async {
    final malformed = _provider((_) async => http.Response('not-json', 200));
    addTearDown(malformed.close);
    await expectLater(_engine(malformed).execute(_request()), throwsA(isA<AIEngineException>()));
    final empty = _provider((_) async => http.Response('{"choices":[{"message":{"content":""}}]}', 200));
    addTearDown(empty.close);
    await expectLater(
      _engine(empty).execute(_request()),
      throwsA(isA<AIEngineException>().having(
        (e) => e.error.message, 'message', contains('no text content'),
      )),
    );
  });

  test('supports text parts and cancellation', () async {
    final provider = _provider((_) async => http.Response(
      '{"choices":[{"message":{"content":[{"type":"text","text":"hello"},{"type":"text","text":" world"}]}}]}',
      200,
    ));
    addTearDown(provider.close);
    expect((await _engine(provider).execute(_request())).text, 'hello world');

    final requestSent = Completer<http.BaseRequest>();
    final response = Completer<http.StreamedResponse>();
    final client = _CapturingClient((request) {
      requestSent.complete(request);
      return response.future;
    });
    final cancellable = OpenRouterProvider(apiKeySource: _FakeKeySource(), client: client);
    addTearDown(cancellable.close);
    final token = AICancellationToken();
    final execution = _engine(cancellable).execute(_request(), cancellationToken: token);
    final request = await requestSent.future;
    token.cancel();
    await expectLater(execution, throwsA(isA<AIEngineException>().having(
      (e) => e.error.code, 'code', AIErrorCode.cancelled,
    )));
    expect(request, isA<http.AbortableRequest>());
    response.complete(http.StreamedResponse(
      Stream.value(utf8.encode('{"choices":[{"message":{"content":"late"}}]}')), 200,
    ));
  });
}

AIRequest _request() => const AIRequest(id: 'request-1', prompt: 'Say hello');
AIEngine _engine(AIProvider provider) => AIEngine(provider: provider, timeout: const Duration(seconds: 1));

OpenRouterProvider _provider(
  Future<http.Response> Function(http.Request) handler, {
  OpenRouterApiConfig config = const OpenRouterApiConfig(),
  OpenRouterApiKeySource? apiKeySource,
}) => OpenRouterProvider(
  apiKeySource: apiKeySource ?? _FakeKeySource(),
  config: config,
  client: MockClient(handler),
);

class _FakeKeySource implements OpenRouterApiKeySource {
  _FakeKeySource([this.key = 'test-key']);
  final String? key;
  @override
  Future<String?> readApiKey() async => key;
}

class _CapturingClient extends http.BaseClient {
  _CapturingClient(this._send);
  final Future<http.StreamedResponse> Function(http.BaseRequest) _send;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _send(request);
  @override
  void close() {}
}
