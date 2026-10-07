// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omni_ai/main.dart';

void main() {
  testWidgets('system core page starts the auto-process', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('// OMNI_AI : SYS_CORE'), findsOneWidget);
    expect(find.text('STATUS: ONLINE'), findsOneWidget);
    expect(find.text('ЗАПУСТИТЬ АВТО-ПРОЦЕСС'), findsOneWidget);
    expect(find.text('АВТО-ПРОЦЕСС ИНИЦИАЛИЗИРОВАН'), findsNothing);

    await tester.tap(find.text('ЗАПУСТИТЬ АВТО-ПРОЦЕСС'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('ЗАПУСТИТЬ СНОВА'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('AUTO-PROCESS INITIALIZED'),
      ),
      findsOneWidget,
    );
  });
}
