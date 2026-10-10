import 'dart:async';

import '../models/ai_error.dart';
import '../models/ai_request.dart';
import '../models/ai_response.dart';
import '../providers/ai_provider.dart';

class AIEngine {
  const AIEngine({
    required this.provider,
    this.timeout = const Duration(seconds: 30),
    this.beforeExecute,
  });

  final AIProvider provider;
  final Duration timeout;

  /// Runs setup before a provider can receive a request.
  final Future<void> Function()? beforeExecute;

  Future<AIResponse> execute(
    AIRequest request, {
    AICancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? AICancellationToken();
    if (request.prompt.trim().isEmpty) {
      throw const AIEngineException(
        AIError(
          code: AIErrorCode.invalidRequest,
          message: 'AI request prompt cannot be empty.',
        ),
      );
    }

    try {
      await beforeExecute?.call();
      final providerFuture = provider.complete(
        request,
        cancellationToken: token,
      );
      final response =
          await Future.any<AIResponse>([
            providerFuture,
            _throwWhenCancelled(token),
          ]).timeout(
            timeout,
            onTimeout: () {
              token.cancel();
              throw const AIEngineException(
                AIError(
                  code: AIErrorCode.timeout,
                  message: 'AI provider request timed out.',
                  retryable: true,
                ),
              );
            },
          );

      if (token.isCancelled) {
        throw const AIEngineException(
          AIError(
            code: AIErrorCode.cancelled,
            message: 'AI request cancelled.',
          ),
        );
      }

      return response;
    } on AIEngineException {
      rethrow;
    } catch (error) {
      throw AIEngineException(
        AIError(
          code: AIErrorCode.provider,
          message: error.toString(),
          retryable: true,
        ),
      );
    }
  }

  Future<AIResponse> _throwWhenCancelled(AICancellationToken token) async {
    await token.cancelled;
    throw const AIEngineException(
      AIError(code: AIErrorCode.cancelled, message: 'AI request cancelled.'),
    );
  }
}
