import '../models/news_article.dart';

/// Conservatively finds an already available Russian-language version of a
/// foreign news item. This does not perform network search or translation.
///
/// The matcher deliberately prefers false negatives over silently linking
/// unrelated stories: it requires a shared distinctive title token (or two
/// shared title tokens), compatible topics, and publication dates within a
/// small time window.
class RussianSourceMatcher {
  const RussianSourceMatcher({
    this.maxPublicationGap = const Duration(hours: 72),
  });

  final Duration maxPublicationGap;

  static const _stopWords = <String>{
    'the', 'and', 'for', 'with', 'from', 'that', 'this', 'will', 'into',
    'after', 'before', 'over', 'under', 'about', 'new', 'latest', 'says',
    'said', 'как', 'что', 'это', 'для', 'после', 'перед', 'над', 'под',
    'его', 'ее', 'они', 'она', 'они', 'будет', 'новый', 'новая', 'новые',
    'стало', 'стал', 'стала', 'сообщает', 'сообщил', 'сообщили',
  };

  RussianSourceMatch? findBestMatch(
    NewsArticle original,
    Iterable<NewsArticle> candidates,
  ) {
    if (original.language.toLowerCase() == 'ru') return null;

    final originalTokens = _titleTokens(original.title);
    if (originalTokens.isEmpty) return null;

    RussianSourceMatch? best;
    for (final candidate in candidates) {
      if (candidate.language.toLowerCase() != 'ru') continue;
      if (candidate.sourceUrl.trim().isEmpty ||
          candidate.sourceUrl == original.sourceUrl) {
        continue;
      }

      final gap = original.publishedAt.difference(candidate.publishedAt).abs();
      if (gap > maxPublicationGap) continue;

      final topicOverlap = original.topics.toSet().intersection(
        candidate.topics.toSet(),
      );
      if (original.topics.isNotEmpty &&
          candidate.topics.isNotEmpty &&
          topicOverlap.isEmpty) {
        continue;
      }

      final shared = originalTokens.intersection(_titleTokens(candidate.title));
      final hasNumberedEntity = shared.any(
        (token) => RegExp(r'\d').hasMatch(token),
      );
      if (shared.length < 2 && !hasNumberedEntity) continue;

      final score = shared.length * 10 +
          (topicOverlap.isNotEmpty ? 5 : 0) -
          (gap.inHours ~/ 24);
      if (best == null || score > best.score) {
        best = RussianSourceMatch(article: candidate, score: score);
      }
    }
    return best;
  }

  Set<String> _titleTokens(String title) {
    return title
        .toLowerCase()
        .replaceAll('ё', 'е')
        .split(RegExp(r'[^a-zа-я0-9]+'))
        .where(
          (token) =>
              token.length >= 3 &&
              !_stopWords.contains(token) &&
              token.trim().isNotEmpty,
        )
        .toSet();
  }
}

class RussianSourceMatch {
  const RussianSourceMatch({required this.article, required this.score});

  final NewsArticle article;

  /// Relative ranking score, not a probability.
  final int score;
}
