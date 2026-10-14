import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omni_ai/core/ai_engine/models/ai_error.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';

import 'openrouter_api_config.dart';
import 'openrouter_api_key_source.dart';

/// OpenAI-compatible OpenRouter chat completions. It deliberately does not
/// request any paid web-search tool and never selects a paid fallback itself.
class OpenRouterProvider implements AIProvider {
  OpenRouterProvider({
    required this.apiKeySource,
    this.config = const OpenRouterApiConfig(),
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  static const providerId = 'openrouter';

  final OpenRouterApiKeySource apiKeySource;
  final OpenRouterApiConfig config;
  final http.Client _client;
  final bool _ownsClient;

  @override
  String get id => providerId;

  @override
  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  }) async {
    try {
      final apiKey = (await apiKeySource.readApiKey())?.trim();
      if (apiKey == null || apiKey.isEmpty) {
        throw const AIEngineException(
          AIError(
            code: AIErrorCode.invalidRequest,
            message: 'Облачный AI не настроен: нет ключа OpenRouter.',
          ),
        );
      }
      if (cancellationToken.isCancelled) {
        throw const AIEngineException(
          AIError(
            code: AIErrorCode.cancelled,
            message: 'OpenRouter request cancelled.',
          ),
        );
      }

      final messages = <Map<String, String>>[
        if (request.systemInstruction?.trim().isNotEmpty == true)
          {'role': 'system', 'content': request.systemInstruction!.trim()},
        {'role': 'user', 'content': request.prompt},
      ];
      final apiRequest =
          http.AbortableRequest(
              'POST',
              Uri.parse(config.endpoint),
              abortTrigger: cancellationToken.cancelled,
            )
            ..headers.addAll({
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': '***',
              'HTTP-Referer': config.siteUrl,
              'X-Title': config.appName,
            })
            ..body = jsonEncode({
              'model': config.model,
              'messages': messages,
              'stream': false,
              if (request.metadata['enableWebSearch'] == true)
                'tools': [
                  {
                    'type': 'openrouter:web_search',
                    'parameters': {
                      'engine': 'parallel',
                      'max_results': 3,
                      'max_total_results': 5,
                      'search_context_size': 'low',
                    },
                  },
                ],
            });

      final streamedResponse = await _client.send(apiRequest);
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _apiError(response);
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        throw _malformedResponse('Expected a JSON object.');
      }
      final choices = payload['choices'];
      if (choices is! List || choices.isEmpty || choices.first is! Map) {
        throw _malformedResponse('Response does not contain choices.');
      }
      final message = (choices.first as Map)['message'];
      if (message is! Map) {
        throw _malformedResponse('Response does not contain a message.');
      }
      final content = message['content'];
      final text = _extractText(content);
      if (text.trim().isEmpty) {
        throw _malformedResponse('Response contains no text content.');
      }

      final annotations = message['annotations'];
      final citations = _extractCitations(annotations);
      final usage = payload['usage'];
      final serverToolUse = usage is Map ? usage['server_tool_use'] : null;
      final searchRequests = serverToolUse is Map
          ? serverToolUse['web_search_requests']
          : null;

      return AIResponse(
        requestId: request.id,
        text: text,
        providerId: id,
        generatedAt: DateTime.now(),
        metadata: {
          'model': payload['model'] is String ? payload['model'] : config.model,
          if (payload['id'] is String) 'responseId': payload['id'],
          'webSearchEnabled': request.metadata['enableWebSearch'] == true,
          if (request.metadata['enableWebSearch'] == true)
            'webSearchCitations': citations,
          if (searchRequests is num) 'webSearchRequests': searchRequests,
        },
      );
    } on AIEngineException {
      rethrow;
    } on http.RequestAbortedException {
      if (cancellationToken.isCancelled) {
        throw const AIEngineException(
          AIError(
            code: AIErrorCode.cancelled,
            message: 'OpenRouter request cancelled.',
          ),
        );
      }
      throw _providerError('OpenRouter request was aborted.');
    } on http.ClientException catch (error) {
      throw _providerError('OpenRouter transport failed: ${error.message}');
    } on FormatException catch (error) {
      throw _malformedResponse(error.message);
    } on Object catch (error) {
      throw _providerError('OpenRouter request failed: $error');
    }
  }

  String _extractText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map>()
          .where((part) => part['type'] == 'text')
          .map((part) => part['text'])
          .whereType<String>()
          .join();
    }
    return '';
  }

  List<Map<String, Object?>> _extractCitations(Object? annotations) {
    if (annotations is! List) return const [];
    final citations = <Map<String, Object?>>[];
    for (final annotation in annotations.whereType<Map>()) {
      if (annotation['type'] != 'url_citation') continue;
      final citation = annotation['url_citation'];
      if (citation is! Map) continue;
      final url = citation['url'];
      final uri = url is String ? Uri.tryParse(url) : null;
      if (uri == null ||
          uri.scheme.toLowerCase() != 'https' ||
          uri.host.isEmpty) {
        continue;
      }
      citations.add({
        'url': url,
        if (citation['title'] is String) 'title': citation['title'],
        if (citation['content'] is String) 'content': citation['content'],
      });
    }
    return List<Map<String, Object?>>.unmodifiable(citations);
  }

  AIEngineException _apiError(http.Response response) {
    var detail = 'HTTP ${response.statusCode}';
    try {
      final payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic> && payload['error'] is Map) {
        final message = (payload['error'] as Map)['message'];
        if (message is String && message.isNotEmpty) detail = message;
      }
    } on FormatException {
      // Keep HTTP status if the body isn't JSON.
    }
    final status = response.statusCode;
    return AIEngineException(
      AIError(
        code: AIErrorCode.provider,
        message: 'OpenRouter API returned $status: $detail',
        retryable: status == 429 || status >= 500,
      ),
    );
  }

  AIEngineException _malformedResponse(String detail) => AIEngineException(
    AIError(
      code: AIErrorCode.provider,
      message: 'OpenRouter returned a malformed response: $detail',
      retryable: true,
    ),
  );

  AIEngineException _providerError(String message) => AIEngineException(
    AIError(code: AIErrorCode.provider, message: message, retryable: true),
  );

  void close() {
    if (_ownsClient) _client.close();
  }
}
