import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/telegram/data/telegram_post.dart';
import 'package:omni_ai/core/network/network_service.dart';

class TelegramParserService {
  const TelegramParserService({this.networkService = const NetworkService()});

  final NetworkService networkService;

  /// No production Telegram API/parser is wired yet. Return an empty feed
  /// rather than presenting hard-coded sample posts as live channel updates.
  Future<List<TelegramPost>> fetchPosts(UserPreferences preferences) async {
    return const <TelegramPost>[];
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
