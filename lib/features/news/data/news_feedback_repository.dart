import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum NewsReaction { like, dislike, opened }

class NewsReactionRecord {
  const NewsReactionRecord({
    required this.articleId,
    required this.reaction,
    required this.topics,
    required this.updatedAt,
  });

  final String articleId;
  final NewsReaction reaction;
  final List<String> topics;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'articleId': articleId,
    'reaction': reaction.name,
    'topics': topics,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static NewsReactionRecord? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['articleId'];
    final reactionName = value['reaction'];
    final topics = value['topics'];
    final updatedAt = value['updatedAt'];
    if (id is! String || id.isEmpty || reactionName is! String ||
        topics is! List || updatedAt is! String) {
      return null;
    }
    final reaction = NewsReaction.values.where((item) => item.name == reactionName);
    final date = DateTime.tryParse(updatedAt);
    if (reaction.isEmpty || date == null) return null;
    return NewsReactionRecord(
      articleId: id,
      reaction: reaction.first,
      topics: topics.whereType<String>().map(_normalize).where((s) => s.isNotEmpty).toSet().toList(),
      updatedAt: date,
    );
  }

  static String _normalize(String value) => value.trim().toLowerCase();
}

/// Persists explicit reactions locally. No article text, account data or URLs are stored.
abstract interface class NewsFeedbackStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class NewsFeedbackRepository {
  NewsFeedbackRepository({NewsFeedbackStore? store})
      : _store = store ?? _SharedPreferencesNewsFeedbackStore();

  static const storageKey = 'omni_ai.news_reactions.v1';
  final NewsFeedbackStore _store;

  Future<List<NewsReactionRecord>> load() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map(NewsReactionRecord.fromJson).whereType<NewsReactionRecord>().toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> record({
    required String articleId,
    required NewsReaction reaction,
    required Iterable<String> topics,
    DateTime? now,
  }) async {
    final normalizedId = articleId.trim();
    if (normalizedId.isEmpty) return;
    final records = await load();
    records.removeWhere((record) => record.articleId == normalizedId);
    final safeTopics = topics.map((topic) => topic.trim().toLowerCase())
        .where((topic) => topic.length >= 2).toSet().toList()..sort();
    records.add(NewsReactionRecord(
      articleId: normalizedId,
      reaction: reaction,
      topics: safeTopics,
      updatedAt: now ?? DateTime.now(),
    ));
    // Bound local storage so a long-running feed cannot grow indefinitely.
    records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final bounded = records.take(500).map((record) => record.toJson()).toList();
    await _store.write(storageKey, jsonEncode(bounded));
  }

  Future<Map<String, double>> interestWeights({DateTime? now}) async {
    final reference = now ?? DateTime.now();
    final weights = <String, double>{};
    for (final record in await load()) {
      final ageDays = reference.difference(record.updatedAt).inDays;
      final recency = ageDays <= 14 ? 1.0 : ageDays <= 90 ? 0.7 : 0.35;
      final reactionWeight = switch (record.reaction) {
        NewsReaction.like => 3.0,
        NewsReaction.dislike => -4.0,
        NewsReaction.opened => 0.25,
      };
      for (final topic in record.topics) {
        weights.update(topic, (value) => value + reactionWeight * recency,
            ifAbsent: () => reactionWeight * recency);
      }
    }
    return Map.unmodifiable(weights);
  }
}

class _SharedPreferencesNewsFeedbackStore implements NewsFeedbackStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) => _preferences.setString(key, value);
}
