import '../models/ai_error.dart';
import '../models/ai_request.dart';
import '../models/ai_response.dart';
import 'ai_provider.dart';
import 'ai_streaming_provider.dart';

/// The destination policy for AI requests.
enum AIExecutionMode { automatic, local, cloud }

/// Routes requests through the shared AI engine.
///
/// Automatic mode keeps app-control commands and greetings on-device and sends
/// recommendation, research, news, and other conversational requests to cloud.
class RoutingAIProvider implements AIProvider, AIStreamingProvider {
  RoutingAIProvider({
    required this.localProvider,
    required this.cloudProvider,
    AIExecutionMode initialMode = AIExecutionMode.automatic,
  }) : mode = initialMode;

  final AIProvider localProvider;
  final AIProvider cloudProvider;
  AIExecutionMode mode;

  @override
  String get id => switch (mode) {
    AIExecutionMode.automatic => 'auto-router',
    AIExecutionMode.local => localProvider.id,
    AIExecutionMode.cloud => cloudProvider.id,
  };

  AIProvider _providerForMode(AIExecutionMode selectedMode, String prompt) {
    return switch (selectedMode) {
      AIExecutionMode.local => localProvider,
      AIExecutionMode.cloud => cloudProvider,
      AIExecutionMode.automatic =>
        _isLocalTask(prompt) ? localProvider : cloudProvider,
    };
  }

  bool _isLocalTask(String prompt) {
    final normalized = prompt.trim().toLowerCase();
    if (normalized.isEmpty) return true;

    final localCommand = RegExp(
      r'^(привет|здравствуй|здравствуйте|доброе утро|добрый вечер|'
      r'спасибо|пока|открой (настройки|приложение|чат|новости|медиа)|перейди|закрой|отмени|'
      r'обнови|останови|запусти|включи|выключи|'
      r'добавь в избранное|удали из избранного|'
      r'покажи избранное|покажи настройки|открой настройки|'
      r'покажи статус|статус приложения|help|hi|hello|thanks)\b',
      caseSensitive: false,
    );
    if (localCommand.hasMatch(normalized)) return true;

    final cloudIntent = RegExp(
      r'(посоветуй|рекоменд|подбери|похож|сравни|объясни|расскажи|'
      r'почему|как лучше|что выбрать|фильм|кино|сериал|аниме|манг|'
      r'новост|дайджест|анализ|проанализ|спланируй|придумай|'
      r'переведи|найди информацию|что такое|как работает|'
      r'составь список|плюсы и минусы|news|recommend|movie|film|'
      r'series|anime|manga|compare|explain|why|summarize|research)',
      caseSensitive: false,
    );
    if (cloudIntent.hasMatch(normalized)) return false;

    final words = normalized.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    return words.length <= 3 &&
        !normalized.contains('?') &&
        !normalized.contains('？');
  }

  @override
  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  }) async {
    if (cancellationToken.isCancelled) {
      throw const AIEngineException(
        AIError(code: AIErrorCode.cancelled, message: 'AI request cancelled.'),
      );
    }

    final selected = _providerForMode(mode, request.prompt);
    return selected.complete(request, cancellationToken: cancellationToken);
  }

  @override
  Future<AIResponse> completeStreaming(
    AIRequest request, {
    required AICancellationToken cancellationToken,
    required void Function(String token) onToken,
  }) async {
    if (cancellationToken.isCancelled) {
      throw const AIEngineException(
        AIError(code: AIErrorCode.cancelled, message: 'AI request cancelled.'),
      );
    }

    final selected = _providerForMode(mode, request.prompt);
    if (selected is AIStreamingProvider) {
      return selected.completeStreaming(
        request,
        cancellationToken: cancellationToken,
        onToken: onToken,
      );
    }
    final response = await selected.complete(
      request,
      cancellationToken: cancellationToken,
    );
    if (response.text.isNotEmpty) onToken(response.text);
    return response;
  }
}
