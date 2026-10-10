import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/services/ai_context_manager.dart';

void main() {
  const manager = AIContextManager();

  test('adds recent conversation before the current user message', () {
    final prepared = manager.prepareRequest(
      request: const AIRequest(id: 'r1', prompt: 'And what about tomorrow?'),
      conversationHistory: const [
        AIContextMessage(
          role: AIConversationRole.user,
          content: 'Plan a trip.',
        ),
        AIContextMessage(
          role: AIConversationRole.assistant,
          content: 'Where would you like to go?',
        ),
      ],
    );

    expect(prepared.prompt, contains('User: Plan a trip.'));
    expect(
      prepared.prompt,
      contains('Assistant: Where would you like to go?'),
    );
    expect(
      prepared.prompt,
      endsWith('Current user message:\nAnd what about tomorrow?'),
    );
    expect(prepared.id, 'r1');
  });

  test('does not create persistent memory from conversation history', () {
    final prepared = manager.prepareRequest(
      request: const AIRequest(id: 'r2', prompt: 'Hello'),
      conversationHistory: const [
        AIContextMessage(
          role: AIConversationRole.user,
          content: 'Remember that I like blue.',
        ),
      ],
    );

    expect(prepared.systemInstruction, isNull);
    expect(prepared.prompt, contains('Remember that I like blue.'));
  });

  test('includes only explicitly supplied memories in system instruction', () {
    final prepared = manager.prepareRequest(
      request: const AIRequest(
        id: 'r3',
        prompt: 'Suggest something.',
        systemInstruction: 'Be concise.',
      ),
      explicitMemories: const ['Prefers short answers', 'Likes hiking'],
    );

    expect(prepared.systemInstruction, contains('Be concise.'));
    expect(prepared.systemInstruction, contains('Prefers short answers'));
    expect(prepared.systemInstruction, contains('Likes hiking'));
  });

  test('bounds history and memory context', () {
    const bounded = AIContextManager(
      maxHistoryMessages: 2,
      maxHistoryCharacters: 24,
      maxMemoryCharacters: 10,
    );
    final prepared = bounded.prepareRequest(
      request: const AIRequest(id: 'r4', prompt: 'Current'),
      conversationHistory: const [
        AIContextMessage(
          role: AIConversationRole.user,
          content: 'old',
        ),
        AIContextMessage(
          role: AIConversationRole.assistant,
          content: 'middle',
        ),
        AIContextMessage(
          role: AIConversationRole.user,
          content: 'the most recent history message',
        ),
      ],
      explicitMemories: const ['123456789', 'abcdefghi'],
    );

    expect(prepared.prompt.length, lessThanOrEqualTo(24 + 100));
    expect(prepared.prompt, contains('Current'));
    expect(prepared.systemInstruction!.length, lessThan(100));
    expect(
      prepared.systemInstruction,
      contains('User-approved saved memories'),
    );
  });

  test('leaves a request without context unchanged', () {
    const request = AIRequest(
      id: 'r5',
      prompt: 'Just this prompt',
      systemInstruction: 'Use plain language.',
    );

    final prepared = manager.prepareRequest(request: request);

    expect(prepared.prompt, request.prompt);
    expect(prepared.systemInstruction, request.systemInstruction);
    expect(prepared.metadata, request.metadata);
  });
}
