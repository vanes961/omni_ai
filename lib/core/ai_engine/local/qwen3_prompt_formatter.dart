/// Qwen3 Instruct prompt formatting and defensive response cleanup.
class Qwen3PromptFormatter {
  const Qwen3PromptFormatter._();

  static String format({required String prompt, String? systemInstruction}) {
    final system = systemInstruction?.trim();
    return <String>[
      if (system != null && system.isNotEmpty)
        '<|im_start|>system\n$system\n<|im_end|>',
      // Qwen3 supports /no_think to request a direct user-facing answer.
      '<|im_start|>user\n${prompt.trim()}\n/no_think\n<|im_end|>',
      '<|im_start|>assistant\n',
    ].join('\n');
  }

  /// Returns a safe prefix for streaming without exposing internal reasoning
  /// or partial control markers.
  static String visiblePrefix(String output) {
    var text = output;
    while (true) {
      final start = RegExp(r'<think>', caseSensitive: false).firstMatch(text);
      if (start == null) break;
      final end = RegExp(
        r'</think>',
        caseSensitive: false,
      ).firstMatch(text.substring(start.end));
      if (end == null) {
        text = text.substring(0, start.start);
        break;
      }
      text =
          '${text.substring(0, start.start)}${text.substring(start.end + end.end)}';
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
      if (index >= 0) text = text.substring(0, index);
    }

    const partialMarkers = [
      '<think>',
      '</think>',
      '<|im_end|>',
      '<|endoftext|>',
      '<|im_start|>user',
      '<|im_start|>assistant',
      '\nUser:',
      '\nAssistant:',
    ];
    var safeEnd = text.length;
    for (final marker in partialMarkers) {
      for (var length = 1; length < marker.length; length++) {
        if (text.endsWith(marker.substring(0, length))) {
          final candidateEnd = text.length - length;
          if (candidateEnd < safeEnd) safeEnd = candidateEnd;
        }
      }
    }
    text = text.substring(0, safeEnd);

    final trimmed = text.trim();
    if (RegExp(
      r'^(?:Assistant|User)\s*:\s*$',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return '';
    }
    return trimmed;
  }

  /// Removes special end markers, internal reasoning, and accidental turns.
  static String sanitize(String output) {
    var text = output.trim();

    while (true) {
      final start = RegExp(r'<think>', caseSensitive: false).firstMatch(text);
      if (start == null) break;
      final end = RegExp(
        r'</think>',
        caseSensitive: false,
      ).firstMatch(text.substring(start.end));
      if (end == null) {
        text = text.substring(0, start.start).trim();
        break;
      }
      text =
          '${text.substring(0, start.start)}${text.substring(start.end + end.end)}';
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
