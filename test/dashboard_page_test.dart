import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:omni_ai/features/dashboard/presentation/dashboard_page.dart';
import 'package:omni_ai/features/media/presentation/media_page.dart';
import 'package:omni_ai/features/news/presentation/news_center_page.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/settings/presentation/pages/network_settings_page.dart';

void main() {
  testWidgets('shows current dashboard destinations without legacy feed UI', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = UserPreferences()
      ..tgChannels = <String>['Legacy Telegram channel']
      ..favoriteTitles = <String>['Legacy demo title']
      ..voiceDubbing = <String>['Legacy dubbing provider'];

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(preferences: preferences, initialTab: 2),
      ),
    );
    await tester.pump();

    expect(find.text('OMNI AI'), findsOneWidget);
    expect(find.text('Ваш личный помощник'), findsOneWidget);
    expect(find.byTooltip('Проверить приложение'), findsOneWidget);
    expect(find.text('Лента'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('Медиа'), findsOneWidget);
    expect(find.text('Избранное'), findsOneWidget);
    expect(find.text('Семья & Здоровье'), findsNothing);
    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('Legacy Telegram channel'), findsNothing);
    expect(find.text('Life Free Hub'), findsNothing);
    expect(find.text('Legacy demo title'), findsNothing);

    await tester.tap(find.text('Медиа'));
    await tester.pump();
    expect(find.byType(MediaPage), findsOneWidget);
    expect(find.byKey(const ValueKey('media-search')), findsOneWidget);

    await tester.tap(find.text('Настройки'));
    await tester.pump();
    expect(find.byType(NetworkSettingsPage), findsOneWidget);
    expect(find.text('Авто-выбор зеркал'), findsOneWidget);

    await tester.tap(find.text('Лента'));
    await tester.pump();
    expect(find.byType(NewsCenterPage), findsOneWidget);
  });
}
