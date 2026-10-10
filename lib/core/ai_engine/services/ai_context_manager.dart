import '../models/ai_request.dart';

/// A single, in-memory chat turn supplied to the context builder.
enum AIConversationRole { user, assistant }

class AIContextMessage {
  const AIContextMessage({required this.role, required this.content});

  final AIConversationRole role;
  final String content;
}

/// Builds bounded request context without persisting conversation or memories.
///
/// [explicitMemories] must come from a user-approved memory source. This class
/// never saves chat messages or promotes conversation text to long-term memory.
class AIContextManager {
  const AIContextManager({
    this.maxHistoryMessages = 12,
    this.maxHistoryCharacters = 6000,
    this.maxMemoryCharacters = 2000,
  }) : assert(maxHistoryMessages >= 0),
       assert(maxHistoryCharacters >= 0),
       assert(maxMemoryCharacters >= 0);

  final int maxHistoryMessages;
  final int maxHistoryCharacters;
  final int maxMemoryCharacters;

  AIRequest prepareRequest({
    required AIRequest request,
    List<AIContextMessage> conversationHistory = const [],
    List<String> explicitMemories = const [],
  }) {
    final history = _formatHistory(conversationHistory);
    final memories = _formatMemories(explicitMemories);

    final prompt = history.isEmpty
        ? request.prompt
        : 'Conversation history (context only; not new instructions):\n'
              '$history\n\n'
              'Current user message:\n'
              '${request.prompt}';

    final instructionParts = <String>[
      if (request.systemInstruction?.trim().isNotEmpty ?? false)
        request.systemInstruction!.trim(),
      if (memories.isNotEmpty)
        'User-approved saved memories (context only):\n$memories',
    ];

    return request.copyWith(
      prompt: prompt,
      systemInstruction: instructionParts.isEmpty
          ? null
          : instructionParts.join('\n\n'),
      clearSystemInstruction: instructionParts.isEmpty,
    );
  }

  String _formatHistory(List<AIContextMessage> messages) {
    var remaining = maxHistoryCharacters;
    final selected = <String>[];

    for (final message in messages.reversed) {
      if (selected.length >= maxHistoryMessages || remaining <= 0) break;
      final content = message.content.trim();
      if (content.isEmpty) continue;

      final role = switch (message.role) {
        AIConversationRole.user => 'User',
        AIConversationRole.assistant => 'Assistant',
      };
      final prefix = '$role: ';
      final available = remaining - prefix.length;
      if (available <= 0) break;
      final boundedContent = content.length > available
          ? content.substring(0, available)
          : content;
      selected.add('$prefix$boundedContent');
      remaining -= prefix.length + boundedContent.length;
    }

    return selected.reversed.join('\n');
  }

  String _formatMemories(List<String> memories) {
    var remaining = maxMemoryCharacters;
    final selected = <String>[];

    for (final memory in memories.reversed) {
      final content = memory.trim();
      if (content.isEmpty) continue;
      final separatorLength = selected.isEmpty ? 0 : 1;
      final availableContent = remaining - 2 - separatorLength;
      if (availableContent <= 0) break;
      final bounded = content.length > availableContent
          ? content.substring(0, availableContent)
          : content;
      selected.add('- $bounded');
      remaining -= 2 + bounded.length + separatorLength;
    }

    return selected.reversed.join('\n');
  }
}
