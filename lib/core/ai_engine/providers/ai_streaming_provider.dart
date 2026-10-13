import '../models/ai_request.dart';
import '../models/ai_response.dart';
import 'ai_provider.dart';

/// Optional capability for providers that can expose generated text incrementally.
abstract interface class AIStreamingProvider {
  Future<AIResponse> completeStreaming(
    AIRequest request, {
    required AICancellationToken cancellationToken,
    required void Function(String token) onToken,
  });
}
