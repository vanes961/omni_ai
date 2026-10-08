import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/dashboard/presentation/dashboard_page.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

void main() {
  testWidgets('shows guard, swipe feed, and four navigation destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: DashboardPage(preferences: UserPreferences())),
    );

    expect(find.text('AI-GUARD ACTIVE'), findsOneWidget);
    expect(find.text('МЕДИА-МОДУЛЬ'), findsOneWidget);
    expect(find.text('Лента'), findsOneWidget);
    expect(find.text('Медиа'), findsOneWidget);
    expect(find.text('Семья & Здоровье'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('TELEGRAM // NEWS'), findsOneWidget);

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('04 // SETTINGS'), findsOneWidget);
  });
}
