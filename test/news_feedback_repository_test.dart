import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/news/data/news_feedback_repository.dart';

void main() {
  late _MemoryNewsFeedbackStore store;
  late NewsFeedbackRepository repository;

  setUp(() {
    store = _MemoryNewsFeedbackStore();
    repository = NewsFeedbackRepository(store: store);
  });

  test('stores a normalized reaction and replaces the previous reaction', () async {
    await repository.record(
      articleId: 'article-1',
      reaction: NewsReaction.like,
      topics: [' Anime ', 'anime', 'Sci-Fi'],
      now: DateTime.utc(2026, 10, 11),
    );
    await repository.record(
      articleId: 'article-1',
      reaction: NewsReaction.dislike,
      topics: ['anime'],
      now: DateTime.utc(2026, 10, 12),
    );

    final records = await repository.load();
    expect(records, hasLength(1));
    expect(records.single.reaction, NewsReaction.dislike);
    expect(records.single.topics, ['anime']);
  });

  test('likes increase and dislikes decrease topic weights', () async {
    await repository.record(
      articleId: 'liked',
      reaction: NewsReaction.like,
      topics: ['space'],
      now: DateTime.utc(2026, 10, 11),
    );
    await repository.record(
      articleId: 'disliked',
      reaction: NewsReaction.dislike,
      topics: ['games'],
      now: DateTime.utc(2026, 10, 11),
    );

    final weights = await repository.interestWeights(now: DateTime.utc(2026, 10, 11));

    expect(weights['space'], 3.0);
    expect(weights['games'], -4.0);
  });

  test('keeps only the most recent 500 article reactions', () async {
    for (var i = 0; i < 505; i++) {
      await repository.record(
        articleId: 'article-$i',
        reaction: NewsReaction.opened,
        topics: ['science'],
        now: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
      );
    }

    expect(await repository.load(), hasLength(500));
    expect((jsonDecode(store.values[NewsFeedbackRepository.storageKey]!) as List), hasLength(500));
  });
}

class _MemoryNewsFeedbackStore implements NewsFeedbackStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
