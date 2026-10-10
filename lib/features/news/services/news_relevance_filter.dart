import 'package:omni_ai/features/news/models/news_article.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';

/// Applies the user's hard relevance boundary before articles reach the feed.
class NewsRelevanceFilter {
  const NewsRelevanceFilter();

  List<NewsArticle> filter(
    Iterable<NewsArticle> articles,
    NewsInterestProfile profile,
  ) {
    final topics = profile.topics.map(_normalize).toSet();
    final languages = profile.languages.map(_normalize).toSet();
    final regions = profile.regions.map(_normalize).toSet();

    final matching = <NewsArticle>[];
    for (final article in articles) {
      if (languages.isNotEmpty &&
          !languages.contains(_normalize(article.language))) {
        continue;
      }
      if (regions.isNotEmpty &&
          (article.region == null ||
              !regions.contains(_normalize(article.region!)))) {
        continue;
      }

      final matchesTopic = article.topics.any(
        (topic) => topics.contains(_normalize(topic)),
      );
      if (matchesTopic ||
          (article.isCritical && profile.includeCriticalOutsideInterests)) {
        matching.add(article);
      }
    }
    matching.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return List<NewsArticle>.unmodifiable(matching);
  }

  String _normalize(String value) => value.trim().toLowerCase();
}
