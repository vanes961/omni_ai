import '../models/ai_error.dart';
import '../models/ai_request.dart';
import '../models/ai_response.dart';
import 'ai_provider.dart';

/// The explicitly selected destination for AI requests.
enum AIExecutionMode { local, cloud }

/// Routes requests to exactly one provider.
///
/// This deliberately does not retry through the other provider if the selected
/// provider fails. That prevents local prompts from silently leaving the
/// device when local inference is unavailable.
class RoutingAIProvider implements AIProvider {
  RoutingAIProvider({
    required this.localProvider,
    required this.cloudProvider,
    AIExecutionMode initialMode = AIExecutionMode.local,
  }) : mode = initialMode;

  final AIProvider localProvider;
  final AIProvider cloudProvider;
  AIExecutionMode mode;

  @override
  String get id => switch (mode) {
    AIExecutionMode.local => localProvider.id,
    AIExecutionMode.cloud => cloudProvider.id,
  };

  @override
  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  }) {
    if (cancellationToken.isCancelled) {
      throw const AIEngineException(
        AIError(code: AIErrorCode.cancelled, message: 'AI request cancelled.'),
      );
    }

    // Select once for this request; never fall back to the other provider.
    final selected = switch (mode) {
      AIExecutionMode.local => localProvider,
      AIExecutionMode.cloud => cloudProvider,
    };
    return selected.complete(request, cancellationToken: cancellationToken);
  }
}
