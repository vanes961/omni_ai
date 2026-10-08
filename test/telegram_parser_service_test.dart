import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/telegram/data/telegram_post.dart';
import 'package:omni_ai/features/telegram/services/telegram_parser_service.dart';

void main() {
  const service = TelegramParserService();

  test(
    'loads only onboarding channels and places pinned posts first',
    () async {
      final preferences = UserPreferences()
        ..tgChannels = ['Игромания', 'Life Free Hub'];

      final posts = await service.fetchPosts(preferences);

      expect(posts, hasLength(3));
      expect(posts.first.channelName, 'Life Free Hub');
      expect(posts.first.isPinned, isTrue);
      expect(
        posts.every(
          (post) => preferences.tgChannels.contains(post.channelName),
        ),
        isTrue,
      );
    },
  );

  test('refresh returns a fresh feed for selected channels', () async {
    final preferences = UserPreferences()..tgChannels = ['Кинопоиск'];

    final posts = await service.refresh(preferences);

    expect(posts, hasLength(1));
    expect(posts.single.channelName, 'Кинопоиск');
  });

  test('filters by message text and channel name', () async {
    final posts = await service.fetchPosts(
      UserPreferences()..tgChannels = ['Life Free Hub', 'Игромания'],
    );

    expect(
      service.filterPosts(posts, query: 'приложений').single.channelName,
      'Life Free Hub',
    );
    expect(service.filterPosts(posts, channelName: 'игромания'), hasLength(2));
  });

  test('returns an empty feed when no channels were selected', () async {
    expect(await service.fetchPosts(UserPreferences()), isEmpty);
  });
}

TelegramPost createTestPost() => TelegramPost(
  id: 'post-test',
  channelName: 'Life Free Hub',
  text: 'Test post with image',
  mediaUrl: 'https://example.com/image.jpg',
  timestamp: DateTime.utc(2026, 10, 8, 9, 30),
  isPinned: true,
  sourceUrl: 'https://t.me/life_free_hub/145',
);
