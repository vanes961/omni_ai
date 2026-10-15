import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/services/ai_context_manager.dart';
import 'package:omni_ai/core/ai_engine/providers/routing_ai_provider.dart';
import 'package:omni_ai/core/di/app_dependencies.dart';
import 'package:omni_ai/features/ai_memory/presentation/ai_memory_manager_dialog.dart';
import 'package:omni_ai/features/news/models/news_article.dart';
import 'package:omni_ai/features/news/data/news_interest_repository.dart';
import 'package:omni_ai/features/news/data/shared_preferences_news_cache.dart';
import 'package:omni_ai/features/news/data/shared_preferences_news_interest_repository.dart';
import 'package:omni_ai/features/news/services/news_chat_context_builder.dart';
import 'package:omni_ai/features/news/services/news_source_localization_service.dart';
import 'package:omni_ai/features/news/services/news_rss_service.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class AIChatPage extends StatefulWidget {
  const AIChatPage({
    required this.dependencies,
    this.newsService,
    this.newsRepository,
    super.key,
  });

  final AppDependencies dependencies;
  final NewsRssService? newsService;
  final NewsInterestRepository? newsRepository;

  @override
  State<AIChatPage> createState() => _AIChatPageState();
}

class _AIChatPageState extends State<AIChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_ChatMessage> _messages = <_ChatMessage>[];
  final SharedPreferencesNewsCache _newsCache = SharedPreferencesNewsCache();
  late final NewsRssService _newsService;
  late final NewsInterestRepository _newsRepository;
  late final bool _ownsNewsService;
  late final bool _ownsNewsRepository;
  final NewsChatContextBuilder _newsContextBuilder =
      const NewsChatContextBuilder();
  AICancellationToken? _activeToken;
  bool _sending = false;
  bool _modeLoading = true;
  String? _modeError;

  @override
  void initState() {
    super.initState();
    _ownsNewsService = widget.newsService == null;
    _newsService = widget.newsService ?? NewsRssService();
    _ownsNewsRepository = widget.newsRepository == null;
    _newsRepository =
        widget.newsRepository ?? SharedPreferencesNewsInterestRepository();
    unawaited(_loadMode());
  }

  Future<void> _loadMode() async {
    try {
      await widget.dependencies.ai.restoreExecutionMode();
    } on Object catch (error) {
      if (mounted) setState(() => _modeError = error.toString());
    } finally {
      if (mounted) setState(() => _modeLoading = false);
    }
  }

  Future<void> _send() async {
    final prompt = _input.text.trim();
    if (prompt.isEmpty || _sending || _modeLoading) return;
    final conversationHistory = _messages
        .where((message) => !message.isError)
        .map(
          (message) => AIContextMessage(
            role: message.isUser
                ? AIConversationRole.user
                : AIConversationRole.assistant,
            content: message.text,
          ),
        )
        .toList(growable: false);
    _input.clear();
    final token = AICancellationToken();
    final requestStopwatch = Stopwatch()..start();
    final streamedOutput = StringBuffer();
    late int assistantMessageIndex;
    setState(() {
      _sending = true;
      _activeToken = token;
      _messages.add(_ChatMessage(text: prompt, isUser: true));
      assistantMessageIndex = _messages.length;
      _messages.add(const _ChatMessage(text: '', isUser: false));
      _modeError = null;
    });
    _scrollToBottom();

    try {
      await widget.dependencies.ai.restoreExecutionMode();
      final savedMemories = await widget.dependencies.aiMemoryRepository
          .getAll();
      var requestPrompt = prompt;
      if (_newsContextBuilder.isNewsRequest(prompt)) {
        var cachedArticles = const <NewsArticle>[];
        try {
          cachedArticles = await _newsCache.loadArticles();
        } on Object {
          // Fresh RSS retrieval below remains available if local cache fails.
        }
        var freshArticles = const <NewsArticle>[];
        var includesFreshResults = false;
        try {
          final profile = await _newsRepository.load();
          // An empty interest profile still has a general discovery feed.
          freshArticles = await _newsService.fetchInternational(profile);
          includesFreshResults = freshArticles.isNotEmpty;
        } on Object {
          // A network/source failure falls back to the cached personalized feed.
        }
        // Apply the same cross-language duplicate detection and bounded
        // translation used by the news feed before giving RSS excerpts to chat.
        // Only cached Russian articles are duplicate-matching candidates:
        // treating every cached foreign-language story as a Russian equivalent
        // can suppress a distinct fresh story with a similar title.
        final cachedRussianArticles = cachedArticles
            .where((article) => article.language.toLowerCase() == 'ru')
            .toList(growable: false);
        final localizedCandidates = await NewsSourceLocalizationService(
          aiEngine: widget.dependencies.ai.engine,
        ).localizeCandidates([...freshArticles, ...cachedRussianArticles]);
        final cachedNonRussianArticles = cachedArticles
            .where((article) => article.language.toLowerCase() != 'ru')
            .toList(growable: false);
        final articles = _newsContextBuilder.mergeArticles(
          fresh: localizedCandidates,
          cached: cachedNonRussianArticles,
        );
        requestPrompt = _newsContextBuilder.buildPrompt(
          prompt,
          articles,
          includesFreshResults: includesFreshResults,
        );
      }
      final response = await widget.dependencies.orchestrator.execute(
        AIRequest(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          prompt: requestPrompt,
          systemInstruction:
              'Отвечай сразу, кратко и по делу, как быстрый помощник. Сначала дай готовый ответ или следующий конкретный шаг; подробности добавляй только если нужны. Не показывай внутренние рассуждения, черновик анализа или содержимое тегов <think>, <analysis> и <reasoning>.',
        ),
        cancellationToken: token,
        conversationHistory: conversationHistory,
        explicitMemories: savedMemories
            .map((memory) => memory.content)
            .toList(growable: false),
        onToken: (chunk) {
          streamedOutput.write(chunk);
          final visibleText = _cleanAssistantAnswer(streamedOutput.toString());
          if (!mounted) return;
          setState(() {
            _messages[assistantMessageIndex] = _ChatMessage(
              text: visibleText,
              isUser: false,
            );
          });
          _scrollToBottom();
        },
      );
      requestStopwatch.stop();
      if (!mounted) return;
      setState(() {
        _messages[assistantMessageIndex] = _ChatMessage(
          text: _cleanAssistantAnswer(response.text),
          isUser: false,
          performance: _localPerformanceLabel(
            response.providerId,
            response.metadata,
            totalDurationMs: requestStopwatch.elapsedMilliseconds,
          ),
        );
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messages[assistantMessageIndex] = _ChatMessage(
          text: token.isCancelled
              ? 'Запрос отменён.'
              : 'Не удалось получить ответ: $error',
          isUser: false,
          isError: !token.isCancelled,
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _activeToken = null;
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _openMemoryManager() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AIMemoryManagerDialog(
        repository: widget.dependencies.aiMemoryRepository,
      ),
    );
  }

  void _cancel() {
    _activeToken?.cancel();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      unawaited(
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  @override
  void dispose() {
    _activeToken?.cancel();
    if (_ownsNewsService) _newsService.dispose();
    if (_ownsNewsRepository) unawaited(_newsRepository.dispose());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.dependencies.ai.executionMode;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: const BoxDecoration(
            color: SystemCorePalette.panel,
            border: Border(bottom: BorderSide(color: SystemCorePalette.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'OMNI AI  /  PERSONAL INTELLIGENCE',
                style: TextStyle(
                  color: SystemCorePalette.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'ЛИЧНЫЙ ПОМОЩНИК',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Долговременная память',
                    onPressed: _openMemoryManager,
                    icon: const Icon(Icons.bookmarks_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    mode == AIExecutionMode.local
                        ? Icons.phone_android
                        : mode == AIExecutionMode.cloud
                        ? Icons.cloud_outlined
                        : Icons.alt_route,
                    size: 15,
                    color: SystemCorePalette.green,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _modeLoading
                        ? 'ЗАГРУЗКА РЕЖИМА...'
                        : mode == AIExecutionMode.local
                        ? 'LOCAL AI — ТОЛЬКО НА УСТРОЙСТВЕ'
                        : mode == AIExecutionMode.cloud
                        ? 'CLOUD AI — ОБЛАЧНЫЕ ЗАПРОСЫ'
                        : 'AUTO AI — ВЫБОР МОДЕЛИ ПО ЗАДАЧЕ',
                    style: const TextStyle(
                      color: SystemCorePalette.green,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              if (_modeError != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Не удалось загрузить режим: $_modeError',
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'Задайте вопрос, чтобы начать.\n\nВ автоматическом режиме OMNI AI выбирает локальную модель для простых команд, а онлайн-ИИ — для рекомендаций и сложных запросов.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: SystemCorePalette.muted,
                        height: 1.6,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: SystemCorePalette.green,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'AI ОБРАБАТЫВАЕТ ЗАПРОС...',
                              style: TextStyle(
                                color: SystemCorePalette.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final message = _messages[index];
                    return Align(
                      alignment: message.isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 560),
                        margin: EdgeInsets.only(
                          bottom: 14,
                          left: message.isUser ? 36 : 0,
                          right: message.isUser ? 0 : 36,
                        ),
                        padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
                        decoration: BoxDecoration(
                          color: message.isError
                              ? Colors.orangeAccent.withValues(alpha: 0.08)
                              : message.isUser
                              ? SystemCorePalette.green.withValues(alpha: 0.12)
                              : SystemCorePalette.panelElevated,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: Radius.circular(message.isUser ? 18 : 5),
                            bottomRight: Radius.circular(message.isUser ? 5 : 18),
                          ),
                          border: Border.all(
                            color: message.isError
                                ? Colors.orangeAccent.withValues(alpha: 0.55)
                                : message.isUser
                                ? SystemCorePalette.green.withValues(alpha: 0.32)
                                : SystemCorePalette.border.withValues(
                                    alpha: 0.42,
                                  ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              message.text,
                              style: TextStyle(
                                color: message.isError
                                    ? Colors.orangeAccent
                                    : Colors.white,
                                height: 1.45,
                                fontSize: 13,
                              ),
                            ),
                            if (message.performance != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                message.performance!,
                                style: const TextStyle(
                                  color: SystemCorePalette.green,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: SystemCorePalette.panel,
            border: const Border(
              top: BorderSide(color: SystemCorePalette.border),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => unawaited(_send()),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Напишите сообщение...',
                    hintStyle: const TextStyle(
                      color: SystemCorePalette.muted,
                      fontSize: 13,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: SystemCorePalette.background,
                    contentPadding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(
                        color: SystemCorePalette.border,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(
                        color: SystemCorePalette.border,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(
                        color: SystemCorePalette.green,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 46,
                height: 46,
                child: IconButton.filled(
                  tooltip: _sending ? 'Отменить запрос' : 'Отправить',
                  onPressed: _sending ? _cancel : _send,
                  style: IconButton.styleFrom(
                    backgroundColor: SystemCorePalette.green,
                    foregroundColor: SystemCorePalette.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(_sending ? Icons.stop_rounded : Icons.arrow_upward),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
    this.performance,
  });

  final String text;
  final bool isUser;
  final bool isError;
  final String? performance;
}

String? _localPerformanceLabel(
  String providerId,
  Map<String, Object?> metadata, {
  required int totalDurationMs,
}) {
  if (providerId != 'local-llama' && metadata['local'] != true) return null;

  final tokenCount = metadata['generatedTokenCount'];
  final durationMs = metadata['generationDurationMs'];
  final tokensPerSecond = metadata['tokensPerSecond'];
  final firstTokenMs = metadata['timeToFirstTokenMs'];
  if (tokenCount is! num || durationMs is! num || tokensPerSecond is! num) {
    return 'LOCAL AI  •  скорость не измерена';
  }

  String decimal(num value) => value.toStringAsFixed(1).replaceAll('.', ',');
  final details = <String>[
    'LOCAL AI',
    '${decimal(tokensPerSecond)} ток/с',
    '${tokenCount.toInt()} токенов',
    'генерация ${decimal(durationMs / 1000)} с',
    'ответ за ${decimal(totalDurationMs / 1000)} с',
    if (firstTokenMs is num) 'первый токен ${decimal(firstTokenMs / 1000)} с',
  ];
  return details.join('  •  ');
}

String _cleanAssistantAnswer(String text) {
  var answer = text;
  for (final tag in ['think', 'analysis', 'reasoning']) {
    answer = answer.replaceAll(
      RegExp('<$tag>[\\s\\S]*?</$tag>', caseSensitive: false),
      '',
    );
    final openingTag = RegExp('<$tag>', caseSensitive: false);
    final closingTag = RegExp('</$tag>', caseSensitive: false);
    final openingMatch = openingTag.firstMatch(answer);
    final closingMatch = closingTag.firstMatch(answer);
    if (openingMatch != null && closingMatch == null) {
      answer = answer.substring(0, openingMatch.start);
    } else if (closingMatch != null && openingMatch == null) {
      answer = answer.substring(closingMatch.end);
    }
  }
  return answer
      .replaceAll(RegExp(r'<\|(?:im_start|im_end|fim_suffix|endoftext)\|>'), '')
      .trim();
}
