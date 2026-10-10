import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/news/models/news_article.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';
import 'package:omni_ai/features/news/services/news_relevance_filter.dart';

void main() {
  const filter = NewsRelevanceFilter();
  final now = DateTime.utc(2026, 10, 10);
  NewsArticle article(
    String id,
    List<String> topics, {
    String language = 'ru',
    String? region,
    bool critical = false,
    int day = 1,
  }) => NewsArticle(
    id: id,
    title: id,
    summary: 'summary',
    sourceName: 'source',
    sourceUrl: 'https://example.com/$id',
    publishedAt: now.add(Duration(days: day)),
    topics: topics,
    language: language,
    region: region,
    isCritical: critical,
  );

  test('only returns selected topics and sorts newest first', () {
    final profile = NewsInterestProfile(topics: ['anime']);
    final result = filter.filter([
      article('game', ['games']),
      article('old-anime', ['anime'], day: 1),
      article('new-anime', ['anime'], day: 2),
    ], profile);

    expect(result.map((item) => item.id), ['new-anime', 'old-anime']);
  });

  test('empty interests do not fill the feed with unrelated articles', () {
    expect(
      filter.filter([
        article('game', ['games']),
      ], const NewsInterestProfile()),
      isEmpty,
    );
  });

  test('critical out-of-interest news requires explicit opt-in', () {
    final critical = article('alert', ['politics'], critical: true);
    expect(filter.filter([critical], const NewsInterestProfile()), isEmpty);
    expect(
      filter.filter([
        critical,
      ], const NewsInterestProfile(includeCriticalOutsideInterests: true)),
      hasLength(1),
    );
  });

  test('language and region restrictions still apply to critical items', () {
    final profile = const NewsInterestProfile(
      includeCriticalOutsideInterests: true,
      languages: ['ru'],
      regions: ['nl'],
    );
    expect(
      filter
          .filter([
            article(
              'english',
              ['other'],
              language: 'en',
              region: 'nl',
              critical: true,
            ),
            article('wrong-region', ['other'], region: 'us', critical: true),
            article('allowed', ['other'], region: 'nl', critical: true),
          ], profile)
          .map((item) => item.id),
      ['allowed'],
    );
  });

  test('normalizes topic, language and region matching and returns immutable results', () {
    final profile = const NewsInterestProfile(
      topics: [' Anime '],
      languages: [' EN '],
      regions: [' US '],
    );
    final matching = article(
      'matching',
      ['anime'],
      language: 'en',
      region: 'us',
    );
    final result = filter.filter([matching], profile);

    expect(result.map((item) => item.id), ['matching']);
    expect(
      () => result.add(article('extra', ['anime'], language: 'en', region: 'us')),
      throwsUnsupportedError,
    );
  });
}
