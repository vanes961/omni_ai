import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/favorites/data/favorite_item.dart';
import 'package:omni_ai/features/favorites/services/favorite_interest_analytics.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/news/models/news_article.dart';

void main() {
  const analytics = FavoriteInterestAnalytics();
  final now = DateTime.utc(2026, 10, 10);

  test('counts categories and gives more weight to explicit interests', () {
    final profile = analytics.analyze([
      _favorite(
        'anime-1',
        FavoriteCategory.anime,
        title: 'Cyberpunk Edgerunners',
        interests: ['Sci-Fi', 'Cyberpunk'],
        addedAt: now,
      ),
      _favorite(
        'manga-1',
        FavoriteCategory.manga,
        title: 'Cyberpunk Manga',
        interests: ['Cyberpunk'],
        addedAt: now,
      ),
    ], now: now);

    expect(profile.totalFavorites, 2);
    expect(profile.countFor(FavoriteCategory.anime), 1);
    expect(profile.countFor(FavoriteCategory.manga), 1);
    expect(profile.interestWeights['cyberpunk'], greaterThan(3.0));
    expect(profile.topInterests.first.key, 'cyberpunk');
  });

  test('ranks matching genres above unrelated media without filtering it out', () {
    final favorites = [
      _favorite(
        'fav-1',
        FavoriteCategory.anime,
        title: 'Cyberpunk Edgerunners',
        interests: ['Cyberpunk', 'Sci-Fi'],
        addedAt: now,
      ),
    ];
    final profile = analytics.analyze(favorites, now: now);
    final matching = _media(
      'match',
      'Neon Future',
      categories: ['Sci-Fi', 'Cyberpunk'],
    );
    final unrelated = _media('other', 'Quiet Garden', categories: ['Drama']);

    final ranked = analytics.rank([unrelated, matching], profile);

    expect(ranked.map((item) => item.id), ['match', 'other']);
    expect(ranked, hasLength(2));
  });

  test('recent favorites weigh more than old favorites', () {
    final recent = analytics.analyze([
      _favorite(
        'recent',
        FavoriteCategory.movie,
        title: 'Space Adventure',
        interests: ['space-opera'],
        addedAt: now,
      ),
    ], now: now);
    final old = analytics.analyze([
      _favorite(
        'old',
        FavoriteCategory.movie,
        title: 'Space Adventure',
        interests: ['space-opera'],
        addedAt: now.subtract(const Duration(days: 365)),
      ),
    ], now: now);

    expect(
      recent.interestWeights['space-opera'],
      greaterThan(old.interestWeights['space-opera']!),
    );
  });

  test('ranks news by saved topics without hiding unrelated articles', () {
    final profile = analytics.analyze([
      _favorite(
        'anime-fav',
        FavoriteCategory.anime,
        title: 'Cyberpunk Edgerunners',
        interests: ['anime', 'cyberpunk'],
        addedAt: now,
      ),
    ], now: now);
    final unrelated = _news('unrelated', topics: ['gardening']);
    final matching = _news('matching', topics: ['anime', 'cyberpunk']);

    final ranked = analytics.rankNews([unrelated, matching], profile);

    expect(ranked.map((article) => article.id), ['matching', 'unrelated']);
    expect(ranked, hasLength(2));
  });

  test('less-interested feedback pushes matching news lower', () {
    final profile = analytics.analyze([
      _favorite(
        'anime-fav',
        FavoriteCategory.anime,
        title: 'Something Else',
        interests: ['anime'],
        addedAt: now,
      ),
    ], now: now);
    final matching = _news('matching', topics: ['anime']);
    final unrelated = _news('unrelated', topics: ['gardening']);

    final ranked = analytics.rankNews(
      [matching, unrelated],
      profile,
      lessInterested: {'anime'},
    );

    expect(ranked.map((article) => article.id), ['unrelated', 'matching']);
    expect(ranked, hasLength(2));
  });

  test('combines favorite and reaction signals in one ranking pass', () {
    final profile = analytics.analyze([
      _favorite(
        'anime-fav',
        FavoriteCategory.anime,
        title: 'Cyberpunk Edgerunners',
        interests: ['anime', 'cyberpunk'],
        addedAt: now,
      ),
    ], now: now);
    final matching = _news('matching', topics: ['anime']);
    final unrelated = _news('unrelated', topics: ['gardening']);

    final ranked = analytics.rankNews(
      [unrelated, matching],
      profile,
      reactionWeights: {'gardening': 10},
    );

    expect(ranked.map((article) => article.id), ['unrelated', 'matching']);
    expect(ranked, hasLength(2));
  });

  test('explains each signal contributing to a news score', () {
    final profile = analytics.analyze([
      _favorite(
        'anime-fav',
        FavoriteCategory.anime,
        title: 'Something Else',
        interests: ['anime'],
        addedAt: now,
      ),
    ], now: now);
    final article = _news('update', topics: ['anime', 'gaming']);
    final breakdown = analytics.explainNewsScore(
      article,
      profile,
      lessInterested: {'anime'},
      reactionWeights: {'gaming': 3},
    );

    expect(breakdown.favoriteInterest, 2);
    expect(breakdown.reaction, 3);
    expect(breakdown.lessInterestedPenalty, -4);
    expect(breakdown.trailerBonus, 0);
    expect(breakdown.categoryBonus, 0.35);
    expect(breakdown.favoriteInterestByTerm, {'anime': 2});
    expect(breakdown.reactionByTopic, {'gaming': 3});
    expect(breakdown.lessInterestedTerms, {'anime'});
    expect(
      analytics.scoreNews(
        article,
        profile,
        lessInterested: {'anime'},
        reactionWeights: {'gaming': 3},
      ),
      breakdown.total,
    );
  });

  test('empty favorites do not alter result order', () {
    final items = [
      _media('a', 'First', categories: ['Drama']),
      _media('b', 'Second', categories: ['Action']),
    ];
    final ranked = analytics.rank(items, analytics.analyze([], now: now));

    expect(ranked.map((item) => item.id), ['a', 'b']);
  });
}

NewsArticle _news(String id, {required List<String> topics}) {
  return NewsArticle(
    id: id,
    title: id,
    summary: '',
    sourceName: 'test',
    sourceUrl: 'https://example.com/$id',
    publishedAt: DateTime.utc(2026, 10, 10),
    topics: topics,
  );
}

FavoriteItem _favorite(
  String id,
  FavoriteCategory category, {
  required String title,
  required List<String> interests,
  required DateTime addedAt,
}) {
  return FavoriteItem(
    id: id,
    title: title,
    category: category,
    addedAt: addedAt,
    interests: interests,
  );
}

MediaItem _media(
  String id,
  String title, {
  required List<String> categories,
}) {
  return MediaItem(
    id: id,
    title: title,
    type: 'Фильм',
    posterUrl: '',
    rating: 0,
    voiceovers: const [],
    videoUrl: '',
    categories: categories,
  );
}
