import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/local/qwen3_prompt_formatter.dart';

void main() {
  group('Qwen3PromptFormatter', () {
    test('formats a request using Qwen3 chat markers', () {
      final prompt = Qwen3PromptFormatter.format(
        systemInstruction: 'Answer in Russian.',
        prompt: '  Привет  ',
      );

      expect(prompt, contains('<|im_start|>system\nAnswer in Russian.'));
      expect(prompt, contains('<|im_start|>user\nПривет\n<|im_end|>'));
      expect(prompt, endsWith('<|im_start|>assistant\n'));
      expect(prompt, isNot(contains('User:')));
      expect(prompt, isNot(contains('Assistant:')));
    });

    test('formats a request without an empty system turn', () {
      final prompt = Qwen3PromptFormatter.format(
        systemInstruction: '  ',
        prompt: 'Hello',
      );

      expect(prompt, startsWith('<|im_start|>user'));
      expect(prompt, isNot(contains('<|im_start|>system')));
    });

    test('removes end markers and accidental continuation turns', () {
      expect(
        Qwen3PromptFormatter.sanitize(
          'Ответ. <|im_end|><|im_start|>user\nПродолжи',
        ),
        'Ответ.',
      );
      expect(
        Qwen3PromptFormatter.sanitize('Assistant: Готово.\nUser: ещё вопрос'),
        'Готово.',
      );
    });

    test('preserves ordinary multi-line response text', () {
      expect(
        Qwen3PromptFormatter.sanitize('Первая строка.\nВторая строка.'),
        'Первая строка.\nВторая строка.',
      );
    });
  });
}
