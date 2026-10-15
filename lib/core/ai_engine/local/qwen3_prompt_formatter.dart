/// Qwen3 Instruct prompt formatting and defensive response cleanup.
class Qwen3PromptFormatter {
  const Qwen3PromptFormatter._();

  static String format({
    required String prompt,
    String? systemInstruction,
  }) {
    final system = systemInstruction?.trim();
    return <String>[
      if (system != null && system.isNotEmpty)
        '<|im_start|>system\n$system\n<|im_end|>',
      // Qwen3 supports /no_think to request a direct user-facing answer.
      '<|im_start|>user\n${prompt.trim()}\n/no_think\n<|im_end|>',
      '<|im_start|>assistant\n',
    ].join('\n');
  }

  /// Removes special end markers and any accidental second turn from output.
  static String sanitize(String output) {
    var text = output.trim();

    // Hide Qwen3 reasoning blocks, including an unfinished block at cutoff.
    while (true) {
      final start = RegExp(r'<think>', caseSensitive: false).firstMatch(text);
      if (start == null) break;
      final end = RegExp(r'</think>', caseSensitive: false).firstMatch(
        text,
        start.end,
      );
      if (end == null) {
        text = text.substring(0, start.start).trim();
        break;
      }
      text = '${text.substring(0, start.start)}${text.substring(end.end)}';
    }

    for (final marker in const [
      '<|im_end|>',
      '<|endoftext|>',
      '<|im_start|>user',
      '<|im_start|>assistant',
      '\nUser:',
      '\nAssistant:',
    ]) {
      final index = text.indexOf(marker);
      if (index >= 0) text = text.substring(0, index).trim();
    }
    text = text.replaceFirst(
      RegExp(r'^(?:Assistant|User)\s*:\s*', caseSensitive: false),
      '',
    );
    return text.trim();
  }
}
