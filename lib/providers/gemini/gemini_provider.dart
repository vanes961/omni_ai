import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omni_ai/core/ai_engine/models/ai_error.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';

import 'gemini_api_config.dart';
import 'gemini_api_key_source.dart';

class GeminiProvider implements AIProvider {
  GeminiProvider({
    required this.apiKeySource,
    this.config = const GeminiApiConfig(),
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  static const providerId = 'gemini';

  final GeminiApiKeySource apiKeySource;
  final GeminiApiConfig config;
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
            message: 'Gemini API key is not configured.',
          ),
        );
      }

      final apiRequest =
          http.AbortableRequest(
              'POST',
              Uri.parse(config.endpoint),
              abortTrigger: cancellationToken.cancelled,
            )
            ..headers.addAll({
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'x-goog-api-key': apiKey,
            })
            ..body = jsonEncode(_buildRequestBody(request));
      final streamedResponse = await _client.send(apiRequest);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _apiError(response);
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        throw _malformedResponse('Expected a JSON object.');
      }

      final outputs = payload['outputs'];
      if (outputs is! List) {
        throw _malformedResponse('Response does not contain outputs.');
      }
      final text = outputs
          .whereType<Map<String, dynamic>>()
          .where((output) => output['type'] == 'text')
          .map((output) => output['text'])
          .whereType<String>()
          .join();
      if (text.trim().isEmpty) {
        throw _malformedResponse('Response contains no text output.');
      }

      return AIResponse(
        requestId: request.id,
        text: text,
        providerId: id,
        generatedAt: DateTime.now(),
        metadata: {
          'model': config.model,
          if (payload['id'] is String) 'interactionId': payload['id'],
        },
      );
    } on AIEngineException {
      rethrow;
    } on http.RequestAbortedException {
      if (cancellationToken.isCancelled) {
        throw const AIEngineException(
          AIError(
            code: AIErrorCode.cancelled,
            message: 'Gemini request cancelled.',
          ),
        );
      }
      throw _providerError('Gemini request was aborted.');
    } on http.ClientException catch (error) {
      throw _providerError('Gemini transport failed: ${error.message}');
    } on FormatException catch (error) {
      throw _malformedResponse(error.message);
    } on Object catch (error) {
      throw _providerError('Gemini request failed: $error');
    }
  }

  Map<String, Object?> _buildRequestBody(AIRequest request) => {
    'model': config.model,
    'input': request.prompt,
    'store': false,
    'system_instruction': ?request.systemInstruction,
  };

  AIEngineException _apiError(http.Response response) {
    var detail = 'HTTP ${response.statusCode}';
    try {
      final payload = jsonDecode(response.body);
      if (payload is Map<String, dynamic> &&
          payload['error'] is Map<String, dynamic>) {
        final message = (payload['error'] as Map<String, dynamic>)['message'];
        if (message is String && message.isNotEmpty) detail = message;
      }
    } on FormatException {
      // Preserve the HTTP status when the error body is not JSON.
    }

    return AIEngineException(
      AIError(
        code: AIErrorCode.provider,
        message: 'Gemini API returned ${response.statusCode}: $detail',
        retryable: response.statusCode == 429 || response.statusCode >= 500,
      ),
    );
  }

  AIEngineException _malformedResponse(String detail) => AIEngineException(
    AIError(
      code: AIErrorCode.provider,
      message: 'Gemini returned a malformed response: $detail',
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
