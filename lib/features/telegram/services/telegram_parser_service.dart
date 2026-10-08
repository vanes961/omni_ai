import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/telegram/data/telegram_post.dart';

class TelegramParserService {
  const TelegramParserService();

  static final List<TelegramPost> _mockPosts = [
    TelegramPost(
      id: 'life-free-hub-145',
      channelName: 'Life Free Hub',
      text: 'Подборка полезных приложений и свежих обновлений за сегодня.',
      mediaUrl:
          'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?w=960&q=80',
      timestamp: DateTime.utc(2026, 10, 8, 9, 40),
      isPinned: true,
      sourceUrl: 'https://t.me/life_free_hub/145',
    ),
    TelegramPost(
      id: 'igromania-827',
      channelName: 'Игромания',
      text:
          'Главные игровые релизы недели: даты, платформы и первые впечатления.',
      mediaUrl:
          'https://images.unsplash.com/photo-1542751371-adc38448a05e?w=960&q=80',
      timestamp: DateTime.utc(2026, 10, 8, 8, 15),
      isPinned: false,
      sourceUrl: 'https://t.me/igromania/827',
    ),
    TelegramPost(
      id: 'tech-brief-302',
      channelName: 'Технологии',
      text: 'Коротко о новых устройствах, исследованиях и разработках.',
      timestamp: DateTime.utc(2026, 10, 7, 18, 5),
      isPinned: false,
      sourceUrl: 'https://t.me/tech_brief/302',
    ),
    TelegramPost(
      id: 'anime-news-511',
      channelName: 'Аниме Новости',
      text: 'Студия объявила дату премьеры нового сезона и показала тизер.',
      mediaUrl:
          'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=960&q=80',
      timestamp: DateTime.utc(2026, 10, 7, 16, 30),
      isPinned: false,
      sourceUrl: 'https://t.me/anime_news/511',
    ),
    TelegramPost(
      id: 'kinopoisk-094',
      channelName: 'Кинопоиск',
      text: 'Новые трейлеры и премьеры этой недели собраны в одном посте.',
      mediaUrl:
          'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?w=960&q=80',
      timestamp: DateTime.utc(2026, 10, 7, 13, 20),
      isPinned: false,
      sourceUrl: 'https://t.me/kinopoisk/94',
    ),
    TelegramPost(
      id: 'igromania-826',
      channelName: 'Игромания',
      text:
          'Свежий разбор инди-релизов, которые стоит добавить в список желаний.',
      timestamp: DateTime.utc(2026, 10, 7, 11, 10),
      isPinned: false,
      sourceUrl: 'https://t.me/igromania/826',
    ),
  ];

  Future<List<TelegramPost>> fetchPosts(UserPreferences preferences) async {
    final selectedChannels = preferences.tgChannels
        .map(_normalize)
        .where((channel) => channel.isNotEmpty)
        .toSet();
    if (selectedChannels.isEmpty) return const [];

    return _sortedPosts(
      _mockPosts.where(
        (post) => selectedChannels.contains(_normalize(post.channelName)),
      ),
    );
  }

  Future<List<TelegramPost>> refresh(UserPreferences preferences) {
    return fetchPosts(preferences);
  }

  List<TelegramPost> filterPosts(
    Iterable<TelegramPost> posts, {
    String query = '',
    String? channelName,
  }) {
    final normalizedQuery = _normalize(query);
    final normalizedChannel = channelName == null
        ? null
        : _normalize(channelName);
    return _sortedPosts(
      posts.where((post) {
        final matchesChannel =
            normalizedChannel == null ||
            _normalize(post.channelName) == normalizedChannel;
        final matchesQuery =
            normalizedQuery.isEmpty ||
            _normalize(post.text).contains(normalizedQuery) ||
            _normalize(post.channelName).contains(normalizedQuery);
        return matchesChannel && matchesQuery;
      }),
    );
  }

  List<TelegramPost> _sortedPosts(Iterable<TelegramPost> posts) {
    final sorted = posts.toList()
      ..sort((first, second) {
        if (first.isPinned != second.isPinned) {
          return first.isPinned ? -1 : 1;
        }
        return second.timestamp.compareTo(first.timestamp);
      });
    return List.unmodifiable(sorted);
  }

  String _normalize(String value) => value.trim().toLowerCase();
}
