// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/models/ai_error.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/providers/gemini/gemini_api_key_source.dart';
import 'package:omni_ai/providers/gemini/gemini_provider.dart';

const _apiKey = String.fromEnvironment('GEMINI_API_KEY');

void main() {
  test(
    'sends a live request through GeminiProvider',
    () async {
      final provider = GeminiProvider(
        apiKeySource: const EnvironmentGeminiApiKeySource(),
      );
      addTearDown(provider.close);

      late final AIResponse response;
      try {
        response = await provider.complete(
          const AIRequest(
            id: 'gemini-live-dev-test',
            prompt: 'Reply with exactly this token: OMNI_GEMINI_DEV_OK',
          ),
          cancellationToken: AICancellationToken(),
        );
      } on Object catch (error, stackTrace) {
        final aiError = error is AIEngineException ? error.error : null;
        final httpStatus = aiError == null
            ? null
            : RegExp(
                r'Gemini API returned (\d{3})',
              ).firstMatch(aiError.message)?.group(1);
        final details = [
          'GeminiProvider.complete() failed',
          'type: ${error.runtimeType}',
          'code: ${aiError?.code.name ?? 'unavailable'}',
          'HTTP status: ${httpStatus ?? 'unavailable'}',
          'message: ${_redactSecret(aiError?.message ?? error.toString())}',
          'stack trace:\n${_redactSecret(stackTrace.toString())}',
        ].join('\n');
        print(details);
        fail(details);
      }

      print('GeminiProvider.complete() succeeded');
      print('providerId: ${_redactSecret(response.providerId)}');
      print('response: ${_redactSecret(response.text)}');
      expect(response.providerId, GeminiProvider.providerId);
      expect(response.text.trim(), isNotEmpty);
    },
    skip: _apiKey.isEmpty
        ? 'Pass GEMINI_API_KEY using --dart-define to run this live test.'
        : false,
  );
}

String _redactSecret(String value) {
  var redacted = value;
  if (_apiKey.isNotEmpty) {
    redacted = redacted
        .replaceAll(_apiKey, '[REDACTED]')
        .replaceAll(Uri.encodeComponent(_apiKey), '[REDACTED]');
  }
  return redacted.replaceAllMapped(
    RegExp(
      r'(authorization|x-goog-api-key)\s*:\s*[^,\r\n}]+',
      caseSensitive: false,
    ),
    (match) => '${match[1]}: [REDACTED]',
  );
}
