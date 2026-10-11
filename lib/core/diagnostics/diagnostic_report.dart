enum DiagnosticStatus { ok, warning, error, notChecked }

class DiagnosticCheck {
  const DiagnosticCheck({
    required this.name,
    required this.status,
    required this.details,
  });

  final String name;
  final DiagnosticStatus status;
  final String details;
}

class DiagnosticReport {
  const DiagnosticReport({
    required this.createdAt,
    required this.checks,
  });

  final DateTime createdAt;
  final List<DiagnosticCheck> checks;

  int get errors => checks.where((check) => check.status == DiagnosticStatus.error).length;
  int get warnings => checks.where((check) => check.status == DiagnosticStatus.warning).length;

  String toPlainText() {
    final buffer = StringBuffer()
      ..writeln('OMNI AI — диагностический отчёт')
      ..writeln('Время: ${createdAt.toLocal().toIso8601String()}')
      ..writeln('Ошибки: $errors; предупреждения: $warnings')
      ..writeln();
    for (final check in checks) {
      buffer.writeln('[${check.status.name.toUpperCase()}] ${check.name}: ${_sanitize(check.details)}');
    }
    return buffer.toString().trim();
  }

  static String _sanitize(String value) {
    // Reports should contain technical summaries, never request URLs or credentials.
    return value
        .replaceAll(RegExp(r'(api[_-]?key|token|password|secret)\\s*[:=]\\s*\\S+', caseSensitive: false), r'$1=[REDACTED]')
        .replaceAll(RegExp(r'https?://\S+'), '[URL]')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
  }
}

/// Instructions for an optional AI review of the sanitized local report.
const diagnosticAnalysisInstruction = '''
Ты — технический диагност OMNI AI. Анализируй только предоставленный обезличенный отчёт.
Не утверждай, что проверил устройство, сеть или исходный код, если отчёт этого не подтверждает.
Разделяй подтверждённые факты и гипотезы; укажи наиболее вероятную причину, недостающие данные,
безопасные шаги проверки и конкретные тесты. Не предлагай автоматически менять код или настройки.
Не запрашивай API-ключи, пароли, личные данные и полные URL.
''';
