import '../models/ai_error.dart';
import '../models/ai_request.dart';
import '../models/ai_response.dart';
import 'ai_provider.dart';
import 'ai_streaming_provider.dart';

/// The destination policy for AI requests.
enum AIExecutionMode { automatic, local, cloud }

/// Routes requests through the shared AI engine.
///
/// Automatic mode prefers on-device inference for general reasoning and only
/// selects cloud for requests that explicitly need fresh external information.
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
        _requiresFreshExternalInformation(prompt)
            ? cloudProvider
            : localProvider,
    };
  }

  bool _requiresFreshExternalInformation(String prompt) {
    final normalized = prompt.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    // Use cloud when the user asks for news or clearly requests current facts,
    // live updates, or an explicit internet/web search.
    final externalInformationIntent = RegExp(
      r'(?:покажи|дай|найди|собери|расскажи)\\s+(?:мне\\s+)?'
      r'(?:свежие\\s+|последние\\s+|актуальные\\s+)?новост\\w*|'
      r'новости\\s+(?:про|об?|по)\\s+(?:игр\\w*|технолог\\w*|аниме|манг\\w*|'
      r'наук\\w*|космос\\w*|событи\\w*|мир\\w*)|'
      r'(какие новост\w*|новост\w* (сегодня|мира|за сегодня)|'
      r'дайджест новост\w*|сводка новост\w*|breaking news|latest news|current news|'
      r"today['’]?s news|\bnews\b|"
      r'сегодняшн\w* (новост\w*|событи\w*|сводк\w*)|'
      r'последн\w* (новост\w*|событи\w*|данн\w*|обновлен\w*)|'
      r'свеж\w* (новост\w*|данн\w*|событи\w*)|'
      r'актуальн\w* (курс\w*|цен\w*|данн\w*|информаци\w*)|'
      r'курс\w* валют\w* (сейчас|сегодня)|сколько сейчас стоит|'
      r'какая сейчас цена|кто сейчас (президент|премьер-министр)|'
      r'что произошло сегодня|что случилось сегодня|'
      r'найди в интернет\w*|поищи в интернет\w*|проверь в интернет\w*|'
      r'поиск в интернет\w*|поищи в сет\w*|найди источник\w*|'
      r'со ссылками на источник\w*|проведи веб.?поиск|'
      r'search the web|browse the web|look up online|check online|'
      r'latest updates|current events|live updates)',
      caseSensitive: false,
    );
    return externalInformationIntent.hasMatch(normalized);
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
    try {
      return await selected.complete(
        request,
        cancellationToken: cancellationToken,
      );
    } on Object {
      if (mode != AIExecutionMode.automatic ||
          !identical(selected, cloudProvider) ||
          cancellationToken.isCancelled) {
        rethrow;
      }
      // Automatic mode is allowed to recover locally when the cloud is
      // unavailable. Explicit Cloud mode never silently changes destination.
      return localProvider.complete(
        request,
        cancellationToken: cancellationToken,
      );
    }
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
    var emittedToken = false;

    void forwardToken(String token) {
      if (token.isNotEmpty) emittedToken = true;
      onToken(token);
    }

    try {
      return await _completeSelectedStreaming(
        selected,
        request,
        cancellationToken: cancellationToken,
        onToken: forwardToken,
      );
    } on Object {
      if (mode != AIExecutionMode.automatic ||
          !identical(selected, cloudProvider) ||
          cancellationToken.isCancelled ||
          emittedToken) {
        rethrow;
      }
      // Once cloud text has reached the UI, switching providers would append
      // a second answer to a partial first answer. Only retry before output.
      return _completeSelectedStreaming(
        localProvider,
        request,
        cancellationToken: cancellationToken,
        onToken: onToken,
      );
    }
  }

  Future<AIResponse> _completeSelectedStreaming(
    AIProvider selected,
    AIRequest request, {
    required AICancellationToken cancellationToken,
    required void Function(String token) onToken,
  }) async {
    if (selected is AIStreamingProvider) {
      return (selected as AIStreamingProvider).completeStreaming(
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
