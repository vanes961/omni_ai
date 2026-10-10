import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/telegram/data/telegram_post.dart';
import 'package:omni_ai/features/telegram/services/telegram_parser_service.dart';

void main() {
  const service = TelegramParserService();

  test('does not expose hard-coded sample posts as live Telegram updates', () async {
    final preferences = UserPreferences()
      ..tgChannels = ['Игромания', 'Life Free Hub'];

    expect(await service.fetchPosts(preferences), isEmpty);
    expect(await service.refresh(preferences), isEmpty);
  });

  test('filters explicitly supplied posts by text and channel name', () {
    final posts = [createTestPost()];

    expect(
      service.filterPosts(posts, query: 'test').single.channelName,
      'Life Free Hub',
    );
    expect(service.filterPosts(posts, channelName: 'игромания'), isEmpty);
    expect(
      service.filterPosts(posts, channelName: 'life free hub'),
      hasLength(1),
    );
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
