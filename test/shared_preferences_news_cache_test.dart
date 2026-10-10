import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/news/data/shared_preferences_news_cache.dart';
import 'package:omni_ai/features/news/models/news_article.dart';

void main() {
  test('round-trips personalized articles and digest', () async {
    final store = _MemoryStore();
    final cache = SharedPreferencesNewsCache(store: store);
    final article = NewsArticle(
      id: 'anime-1',
      title: 'New anime season',
      summary: 'A publisher announced a new season.',
      sourceName: 'Anime News',
      sourceUrl: 'https://example.com/anime',
      publishedAt: DateTime.utc(2026, 10, 10, 12),
      topics: const ['anime'],
      language: 'ru',
      region: 'ru',
      isVerified: true,
    );

    await cache.saveArticles(
      [article],
      selectedTopics: const [' Anime ', 'technology', 'anime', ' '],
    );
    await cache.saveDigest('Персональный дайджест');

    // A fresh cache instance simulates restoring the feed after app restart.
    final restoredCache = SharedPreferencesNewsCache(store: store);
    final restored = await restoredCache.loadArticles();

    expect(restored, hasLength(1));
    expect(restored.single.title, article.title);
    expect(restored.single.sourceUrl, article.sourceUrl);
    expect(restored.single.publishedAt, article.publishedAt);
    expect(restored.single.topics, ['anime']);
    expect(restored.single.isVerified, isTrue);
    expect(await restoredCache.loadTopics(), ['anime', 'technology']);
    expect(await restoredCache.loadDigest(), 'Персональный дайджест');
  });


  test('round-trips trailer metadata and source-backed release date', () async {
    final store = _MemoryStore();
    final cache = SharedPreferencesNewsCache(store: store);
    final trailer = NewsArticle(
      id: 'trailer-1',
      title: 'New game trailer',
      summary: 'Official announcement trailer.',
      sourceName: 'Official Channel',
      sourceUrl: 'https://example.com/trailer-page',
      publishedAt: DateTime.utc(2026, 10, 10, 12),
      topics: const ['games'],
      language: 'en',
      contentType: NewsContentType.trailer,
      videoUrl: 'https://video.example/watch/123',
      thumbnailUrl: 'https://video.example/thumb/123.jpg',
      channelName: 'Official Channel',
      releaseDate: DateTime.utc(2027, 3, 4),
      releaseDateSourceUrl: 'https://example.com/release-date',
    );

    await cache.saveArticles([trailer], selectedTopics: const ['games']);
    final restored = await cache.loadArticles();

    expect(restored, hasLength(1));
    expect(restored.single.contentType, NewsContentType.trailer);
    expect(restored.single.videoUrl, trailer.videoUrl);
    expect(restored.single.thumbnailUrl, trailer.thumbnailUrl);
    expect(restored.single.channelName, trailer.channelName);
    expect(restored.single.releaseDate, trailer.releaseDate);
    expect(restored.single.releaseDateSourceUrl, trailer.releaseDateSourceUrl);
  });

  test('loads legacy article cache and ignores unsafe optional video metadata', () async {
    final store = _MemoryStore()
      ..values[SharedPreferencesNewsCache.articlesKey] = jsonEncode([
        {
          'id': 'legacy-1',
          'title': 'Old cached article',
          'summary': 'Saved before video metadata existed.',
          'sourceName': 'Example',
          'sourceUrl': 'https://example.com/legacy',
          'publishedAt': '2026-10-10T12:00:00.000Z',
          'topics': ['anime'],
          'language': 'ru',
          'isVerified': true,
          'videoUrl': 'javascript:alert(1)',
          'thumbnailUrl': 'http://insecure.example/thumb.jpg',
          'releaseDate': '2027-03-04T00:00:00.000Z',
          'releaseDateSourceUrl': 'javascript:alert(1)',
        },
      ]);
    final cache = SharedPreferencesNewsCache(store: store);

    final restored = await cache.loadArticles();

    expect(restored, hasLength(1));
    expect(restored.single.contentType, NewsContentType.article);
    expect(restored.single.videoUrl, isNull);
    expect(restored.single.thumbnailUrl, isNull);
    expect(restored.single.releaseDate, isNull);
    expect(restored.single.releaseDateSourceUrl, isNull);
  });

  test('returns empty data for missing cache and removes empty digest', () async {
    final store = _MemoryStore();
    final cache = SharedPreferencesNewsCache(store: store);

    expect(await cache.loadArticles(), isEmpty);
    expect(await cache.loadDigest(), isNull);
    await cache.saveDigest('  ');
    expect(await cache.loadDigest(), isNull);
  });

  test('clears articles, digest and saved interests together', () async {
    final store = _MemoryStore();
    final cache = SharedPreferencesNewsCache(store: store);
    await cache.saveArticles(const [], selectedTopics: const ['anime']);
    await cache.saveDigest('Старый дайджест');

    await cache.clear();

    expect(await cache.loadArticles(), isEmpty);
    expect(await cache.loadDigest(), isNull);
    expect(await cache.loadTopics(), isNull);
  });

  test('skips cached articles with unsafe links or invalid publication dates', () async {
    final store = _MemoryStore();
    final cache = SharedPreferencesNewsCache(store: store);
    final article = NewsArticle(
      id: 'safe-1',
      title: 'Safe article',
      summary: 'A valid cached article.',
      sourceName: 'Example',
      sourceUrl: 'https://example.com/safe',
      publishedAt: DateTime.utc(2026, 10, 10, 12),
      topics: const ['technology'],
    );

    await cache.saveArticles([article], selectedTopics: const ['technology']);
    final payload = jsonDecode(
      store.values[SharedPreferencesNewsCache.articlesKey]!,
    ) as List<dynamic>;
    final valid = payload.single as Map<String, dynamic>;
    payload
      ..add({
        ...valid,
        'id': 'unsafe-1',
        'sourceUrl': 'javascript:alert(1)',
      })
      ..add({
        ...valid,
        'id': 'undated-1',
        'publishedAt': 'not-a-date',
      });
    store.values[SharedPreferencesNewsCache.articlesKey] = jsonEncode(payload);

    final restored = await cache.loadArticles();

    expect(restored, hasLength(1));
    expect(restored.single.id, 'safe-1');
  });

  test('skips malformed records and duplicate article IDs during recovery', () async {
    final store = _MemoryStore();
    final cache = SharedPreferencesNewsCache(store: store);
    final article = NewsArticle(
      id: 'duplicate-1',
      title: 'First copy',
      summary: 'A valid cached article.',
      sourceName: 'Example',
      sourceUrl: 'https://example.com/first',
      publishedAt: DateTime.utc(2026, 10, 10, 12),
      topics: const ['technology'],
    );
    await cache.saveArticles([article], selectedTopics: const ['technology']);
    final payload = jsonDecode(
      store.values[SharedPreferencesNewsCache.articlesKey]!,
    ) as List<dynamic>;
    final valid = payload.single as Map<String, dynamic>;
    payload
      ..add('not-an-article')
      ..add({...valid, 'id': '   '})
      ..add({
        ...valid,
        'title': 'Duplicate copy',
        'sourceUrl': 'https://example.com/second',
      });
    store.values[SharedPreferencesNewsCache.articlesKey] = jsonEncode(payload);

    final restored = await cache.loadArticles();

    expect(restored, hasLength(1));
    expect(restored.single.title, 'First copy');
  });

  test('writes topic marker before articles to detect interrupted cache saves', () async {
    final store = _MemoryStore();
    final cache = SharedPreferencesNewsCache(store: store);
    final oldArticle = NewsArticle(
      id: 'old-1',
      title: 'Old topic article',
      summary: 'Old cached content.',
      sourceName: 'Example',
      sourceUrl: 'https://example.com/old',
      publishedAt: DateTime.utc(2026, 10, 9, 12),
      topics: const ['anime'],
    );
    await cache.saveArticles([oldArticle], selectedTopics: const ['anime']);
    final oldPayload = store.values[SharedPreferencesNewsCache.articlesKey];
    store.failWriteKey = SharedPreferencesNewsCache.articlesKey;
    final newArticle = NewsArticle(
      id: 'new-1',
      title: 'New topic article',
      summary: 'New content.',
      sourceName: 'Example',
      sourceUrl: 'https://example.com/new',
      publishedAt: DateTime.utc(2026, 10, 10, 12),
      topics: const ['technology'],
    );

    await expectLater(
      cache.saveArticles([newArticle], selectedTopics: const ['technology']),
      throwsStateError,
    );

    expect(oldPayload, isNotNull);
    expect(
      store.values.containsKey(SharedPreferencesNewsCache.articlesKey),
      isFalse,
    );
    expect(await cache.loadArticles(), isEmpty);
    expect(await cache.loadTopics(), ['technology']);
  });

  test('drops malformed cached interests', () async {
    final store = _MemoryStore()
      ..values[SharedPreferencesNewsCache.topicsKey] = '{"topic":"anime"}';
    final cache = SharedPreferencesNewsCache(store: store);

    expect(await cache.loadTopics(), isNull);
    expect(store.values.containsKey(SharedPreferencesNewsCache.topicsKey), isFalse);
  });

  test('drops malformed cached article payload', () async {
    final store = _MemoryStore()
      ..values[SharedPreferencesNewsCache.articlesKey] = '{broken';
    final cache = SharedPreferencesNewsCache(store: store);

    expect(await cache.loadArticles(), isEmpty);
    expect(store.values.containsKey(SharedPreferencesNewsCache.articlesKey), isFalse);
  });
}

class _MemoryStore implements NewsCacheStringStore {
  final values = <String, String>{};
  String? failWriteKey;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (key == failWriteKey) throw StateError('Simulated storage failure.');
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
