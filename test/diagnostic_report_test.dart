import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/diagnostics/diagnostic_report.dart';

void main() {
  test('summarizes checks and redacts secrets and URLs', () {
    final report = DiagnosticReport(
      createdAt: DateTime.utc(2026, 10, 11),
      checks: [
        DiagnosticCheck(
          name: 'News',
          status: DiagnosticStatus.error,
          details: 'api_key=super-secret request https://example.com/private?q=abc',
        ),
        DiagnosticCheck(
          name: 'Network',
          status: DiagnosticStatus.notChecked,
          details: 'No independent probe',
        ),
      ],
    );

    final text = report.toPlainText();

    expect(report.errors, 1);
    expect(text, contains('Ошибки: 1'));
    expect(text, contains('api_key=[REDACTED]'));
    expect(text, isNot(contains('super-secret')));
    expect(text, isNot(contains('https://example.com')));
    expect(text, contains('[NOTCHECKED] Network'));
  });
}
