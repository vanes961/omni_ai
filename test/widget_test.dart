// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/dashboard/presentation/dashboard_page.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/run_history/data/in_memory_run_history_repository.dart';
import 'package:omni_ai/features/onboarding/presentation/onboarding_page.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_page.dart';
import 'package:omni_ai/features/system_core/services/system_core_process_service.dart';
import 'package:omni_ai/main.dart';

void main() {
  testWidgets('system core page starts the auto-process', (
    WidgetTester tester,
  ) async {
    final historyRepository = InMemoryRunHistoryRepository();
    addTearDown(historyRepository.dispose);
    await tester.pumpWidget(
      MaterialApp(home: SystemCorePage(historyRepository: historyRepository)),
    );

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

  testWidgets('replaces system core with onboarding when restarting', (
    WidgetTester tester,
  ) async {
    final historyRepository = InMemoryRunHistoryRepository();
    final processService = SystemCoreProcessService(runner: (_) async {});
    addTearDown(historyRepository.dispose);
    addTearDown(processService.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SystemCorePage(
          service: processService,
          historyRepository: historyRepository,
        ),
      ),
    );

    await tester.tap(find.text('ЗАПУСТИТЬ АВТО-ПРОЦЕСС'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('ЗАПУСТИТЬ СНОВА'), findsOneWidget);

    await tester.ensureVisible(find.text('ЗАПУСТИТЬ СНОВА'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ЗАПУСТИТЬ СНОВА'));
    await tester.pumpAndSettle();

    expect(find.byType(SystemCorePage), findsNothing);
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.text('01 // СФЕРЫ ИНТЕРЕСОВ'), findsOneWidget);
  });

  testWidgets('saves onboarding choices before opening dashboard', (
    WidgetTester tester,
  ) async {
    final store = _MemoryUserPreferencesStore();
    await tester.pumpWidget(
      MaterialApp(home: OnboardingPage(preferencesStore: store)),
    );

    await tester.tap(find.text('Фильмы'));
    await tester.pump();
    for (var step = 0; step < 4; step++) {
      await tester.tap(find.text('ПРОДОЛЖИТЬ'));
      await tester.pumpAndSettle();
    }
    expect(find.text('ЗАПУСТИТЬ ЭКОСИСТЕМУ'), findsOneWidget);

    await tester.tap(find.text('ЗАПУСТИТЬ ЭКОСИСТЕМУ'));
    await tester.pumpAndSettle();

    expect(store.savedPreferences?.categories, ['Фильмы']);
    expect(find.byType(OnboardingPage), findsNothing);
    expect(find.byType(DashboardPage), findsOneWidget);
  });

  testWidgets('restores a saved profile directly to dashboard on app launch', (
    WidgetTester tester,
  ) async {
    final savedPreferences = UserPreferences()..categories = ['Аниме'];
    final store = _MemoryUserPreferencesStore(savedPreferences);

    await tester.pumpWidget(MyApp(preferencesStore: store));
    await tester.pumpAndSettle();

    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);
    expect(find.text('ИНТЕРЕСЫ  //  АНИМЕ'), findsOneWidget);
  });
}

class _MemoryUserPreferencesStore implements UserPreferencesStore {
  _MemoryUserPreferencesStore([this.savedPreferences]);

  UserPreferences? savedPreferences;

  @override
  Future<UserPreferences?> load() async => savedPreferences;

  @override
  Future<void> save(UserPreferences preferences) async {
    savedPreferences = UserPreferences.fromJson(preferences.toJson());
  }
}
