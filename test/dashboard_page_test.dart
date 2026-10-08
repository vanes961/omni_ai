import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/dashboard/presentation/dashboard_page.dart';
import 'package:omni_ai/features/media/presentation/media_page.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/telegram/presentation/widgets/telegram_post_card.dart';
import 'package:omni_ai/features/telegram/data/telegram_post.dart';
import 'package:omni_ai/features/telegram/services/telegram_parser_service.dart';

void main() {
  testWidgets('shows guard, swipe feed, and four navigation destinations', (
    tester,
  ) async {
    final preferences = UserPreferences()..tgChannels = ['Life Free Hub'];
    await tester.pumpWidget(
      MaterialApp(home: DashboardPage(preferences: preferences)),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI-GUARD ACTIVE'), findsOneWidget);
    expect(find.byType(TelegramPostCard), findsOneWidget);
    expect(find.text('Life Free Hub'), findsNWidgets(2));
    expect(find.text('Лента'), findsOneWidget);
    expect(find.text('Медиа'), findsOneWidget);
    expect(find.text('Семья & Здоровье'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);

    await tester.tap(find.text('Медиа'));
    await tester.pumpAndSettle();
    expect(find.byType(MediaPage), findsOneWidget);
    expect(find.byKey(const ValueKey('media-search')), findsOneWidget);

    await tester.tap(find.text('Лента'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('telegram-feed')),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('telegram-feed')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TelegramPostCard), findsOneWidget);

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('04 // SETTINGS'), findsOneWidget);
  });

  testWidgets('pull to refresh requests fresh Telegram posts', (tester) async {
    final parser = _CountingTelegramParser();
    final preferences = UserPreferences()..tgChannels = ['Life Free Hub'];
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(preferences: preferences, telegramService: parser),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('telegram-feed')),
      const Offset(0, 360),
    );
    await tester.pumpAndSettle();

    expect(parser.refreshCount, 1);
    expect(find.text('Refreshed post'), findsOneWidget);
  });
}

class _CountingTelegramParser extends TelegramParserService {
  int refreshCount = 0;

  @override
  Future<List<TelegramPost>> fetchPosts(UserPreferences preferences) async => [
    _refreshPost,
  ];

  @override
  Future<List<TelegramPost>> refresh(UserPreferences preferences) async {
    refreshCount++;
    return [_refreshPost];
  }
}

final _refreshPost = TelegramPost(
  id: 'refresh-post',
  channelName: 'Life Free Hub',
  text: 'Refreshed post',
  timestamp: DateTime.utc(2026, 10, 8),
  isPinned: false,
);
