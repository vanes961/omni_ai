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
          details:
              'api_key=super-secret request https://example.com/private?q=abc',
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
    expect(report.warnings, 0);
    expect(text, contains('Ошибки: 1; предупреждения: 0'));
    expect(text, contains('api_key=[REDACTED]'));
    expect(text, isNot(contains('super-secret')));
    expect(text, isNot(contains('https://example.com')));
    expect(text, contains('[NOTCHECKED] Network'));
  });

  test('redacts common credential labels and flattens multiline details', () {
    final report = DiagnosticReport(
      createdAt: DateTime.utc(2026, 10, 11),
      checks: [
        DiagnosticCheck(
          name: 'Cloud',
          status: DiagnosticStatus.warning,
          details: 'token: abc123\npassword = p@ssword\r\nsecret=hidden',
        ),
      ],
    );

    final text = report.toPlainText();

    expect(report.warnings, 1);
    expect(text, contains('token=[REDACTED]'));
    expect(text, contains('password=[REDACTED]'));
    expect(text, contains('secret=[REDACTED]'));
    expect(text, isNot(contains('abc123')));
    expect(text, isNot(contains('p@ssword')));
    expect(text, isNot(contains('hidden')));
    expect(text, isNot(contains('\npassword')));
    expect(text, isNot(contains('\r')));
  });

  test('empty report has zero errors and warnings', () {
    final report = DiagnosticReport(
      createdAt: DateTime.utc(2026, 10, 11),
      checks: const [],
    );

    expect(report.errors, 0);
    expect(report.warnings, 0);
    expect(report.toPlainText(), contains('Ошибки: 0; предупреждения: 0'));
  });
}
