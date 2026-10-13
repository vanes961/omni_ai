import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/services/ai_context_manager.dart';
import 'package:omni_ai/core/ai_engine/providers/routing_ai_provider.dart';
import 'package:omni_ai/core/di/app_dependencies.dart';
import 'package:omni_ai/features/ai_memory/presentation/ai_memory_manager_dialog.dart';
import 'package:omni_ai/features/news/data/shared_preferences_news_cache.dart';
import 'package:omni_ai/features/news/services/news_chat_context_builder.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class AIChatPage extends StatefulWidget {
  const AIChatPage({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<AIChatPage> createState() => _AIChatPageState();
}

class _AIChatPageState extends State<AIChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_ChatMessage> _messages = <_ChatMessage>[];
  final SharedPreferencesNewsCache _newsCache = SharedPreferencesNewsCache();
  final NewsChatContextBuilder _newsContextBuilder =
      const NewsChatContextBuilder();
  AICancellationToken? _activeToken;
  bool _sending = false;
  bool _modeLoading = true;
  String? _modeError;

  @override
  void initState() {
    super.initState();
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
    setState(() {
      _sending = true;
      _activeToken = token;
      _messages.add(_ChatMessage(text: prompt, isUser: true));
      _modeError = null;
    });
    _scrollToBottom();

    try {
      await widget.dependencies.ai.restoreExecutionMode();
      final savedMemories = await widget.dependencies.aiMemoryRepository
          .getAll();
      var requestPrompt = prompt;
      if (_newsContextBuilder.isNewsRequest(prompt)) {
        try {
          final cachedArticles = await _newsCache.loadArticles();
          requestPrompt = _newsContextBuilder.buildPrompt(
            prompt,
            cachedArticles,
          );
        } on Object catch (_) {
          // A cache/storage problem must not prevent ordinary chat from working.
          requestPrompt = _newsContextBuilder.buildPrompt(prompt, const []);
        }
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
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            text: _cleanAssistantAnswer(response.text),
            isUser: false,
          ),
        );
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            text: token.isCancelled
                ? 'Запрос отменён.'
                : 'Не удалось получить ответ: $error',
            isUser: false,
            isError: !token.isCancelled,
          ),
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
                'KAIROS // NEURAL LINK',
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
                      'AI-КУРАТОР',
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
                        : Icons.cloud_outlined,
                    size: 15,
                    color: SystemCorePalette.green,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _modeLoading
                        ? 'ЗАГРУЗКА РЕЖИМА...'
                        : mode == AIExecutionMode.local
                        ? 'LOCAL AI — ЗАПРОСЫ ОСТАЮТСЯ НА УСТРОЙСТВЕ'
                        : 'CLOUD AI — ЯВНО ВЫБРАННЫЙ ОБЛАЧНЫЙ РЕЖИМ',
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
                      'Задайте вопрос, чтобы начать.\n\nЛокальный режим не переключается в облако автоматически.',
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
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: message.isUser
                              ? SystemCorePalette.green.withValues(alpha: 0.10)
                              : SystemCorePalette.panelElevated,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: message.isError
                                ? Colors.orangeAccent.withValues(alpha: 0.6)
                                : message.isUser
                                ? SystemCorePalette.green.withValues(alpha: 0.4)
                                : Colors.white12,
                          ),
                        ),
                        child: SelectableText(
                          message.text,
                          style: TextStyle(
                            color: message.isError
                                ? Colors.orangeAccent
                                : Colors.white,
                            height: 1.45,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: const BoxDecoration(
            color: SystemCorePalette.panel,
            border: Border(top: BorderSide(color: SystemCorePalette.border)),
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
                  decoration: const InputDecoration(
                    hintText: 'Напишите сообщение...',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.zero),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: _sending ? 'Отменить запрос' : 'Отправить',
                onPressed: _sending ? _cancel : _send,
                icon: Icon(_sending ? Icons.stop : Icons.send),
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
  });

  final String text;
  final bool isUser;
  final bool isError;
}

String _cleanAssistantAnswer(String text) {
  var answer = text;
  for (final tag in ['think', 'analysis', 'reasoning']) {
    answer = answer.replaceAll(
      RegExp('<$tag>[\\s\\S]*?</$tag>', caseSensitive: false),
      '',
    );
    final closingTag = RegExp('</$tag>', caseSensitive: false);
    final closingMatch = closingTag.firstMatch(answer);
    if (closingMatch != null &&
        !RegExp('<$tag>', caseSensitive: false).hasMatch(answer)) {
      answer = answer.substring(closingMatch.end);
    }
  }
  return answer
      .replaceAll(RegExp(r'<\|(?:im_start|im_end|fim_suffix|endoftext)\|>'), '')
      .trim();
}
