import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:omni_ai/features/dashboard/presentation/dashboard_page.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/run_history/data/in_memory_run_history_repository.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_page.dart';
import 'package:omni_ai/features/system_core/services/system_core_process_service.dart';
import 'package:omni_ai/main.dart';

void main() {
  testWidgets('system core page starts and can restart its process', (
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

    expect(find.text('// OMNI_AI : SYS_CORE'), findsOneWidget);
    await tester.tap(find.text('ЗАПУСТИТЬ АВТО-ПРОЦЕСС'));
    await tester.pumpAndSettle();
    expect(find.text('ЗАПУСТИТЬ СНОВА'), findsOneWidget);

    await tester.ensureVisible(find.text('ЗАПУСТИТЬ СНОВА'));
    await tester.tap(find.text('ЗАПУСТИТЬ СНОВА'));
    await tester.pumpAndSettle();
    expect(find.text('ЗАПУСТИТЬ СНОВА'), findsOneWidget);
  });

  testWidgets('restores a saved profile directly to dashboard on app launch', (
    WidgetTester tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final savedPreferences = UserPreferences()..categories = ['Аниме'];
    final store = _MemoryUserPreferencesStore(savedPreferences);

    await tester.pumpWidget(MyApp(preferencesStore: store));
    // The dashboard has repeating animations, so pump a bounded interval
    // instead of waiting for every animation to settle.
    await tester.pump(const Duration(seconds: 4));

    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.text('01 // СФЕРЫ ИНТЕРЕСОВ'), findsNothing);
    expect(find.text('AI-GUARD ACTIVE'), findsOneWidget);
    expect(
      tester
          .widget<DashboardPage>(find.byType(DashboardPage))
          .preferences
          .categories,
      ['Аниме'],
    );
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
