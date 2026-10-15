import 'package:omni_ai/features/favorites/data/favorite_item.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/news/models/news_article.dart';

/// Local, explainable interest profile derived from saved favorites.
class FavoriteInterestProfile {
  const FavoriteInterestProfile({
    required this.categoryCounts,
    required this.interestWeights,
    required this.totalFavorites,
  });

  final Map<FavoriteCategory, int> categoryCounts;
  final Map<String, double> interestWeights;
  final int totalFavorites;

  List<MapEntry<String, double>> get topInterests {
    final entries = interestWeights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return List<MapEntry<String, double>>.unmodifiable(entries.take(12));
  }

  int countFor(FavoriteCategory category) => categoryCounts[category] ?? 0;
}

/// Transparent components of a news ranking score. Positive values boost an
/// article; a negative less-interested value lowers its position.
class NewsScoreBreakdown {
  const NewsScoreBreakdown({
    required this.favoriteInterest,
    required this.reaction,
    required this.lessInterestedPenalty,
    required this.trailerBonus,
    required this.categoryBonus,
    required this.favoriteInterestByTerm,
    required this.reactionByTopic,
    required this.lessInterestedTerms,
  });

  final double favoriteInterest;
  final double reaction;
  final double lessInterestedPenalty;
  final double trailerBonus;
  final double categoryBonus;
  final Map<String, double> favoriteInterestByTerm;
  final Map<String, double> reactionByTopic;
  final Set<String> lessInterestedTerms;

  double get total =>
      favoriteInterest +
      reaction +
      lessInterestedPenalty +
      trailerBonus +
      categoryBonus;
}

/// No network or AI calls: favorites influence ranking on-device only.
class FavoriteInterestAnalytics {
  const FavoriteInterestAnalytics();

  static const _stopWords = <String>{
    'the',
    'and',
    'for',
    'with',
    'from',
    'into',
    'this',
    'that',
    'your',
    'you',
    'are',
    'was',
    'but',
    'not',
    'its',
    'have',
    'has',
    'will',
    'film',
    'movie',
    'series',
    'season',
    'episode',
    'trailer',
    'это',
    'как',
    'что',
    'для',
    'или',
    'при',
    'над',
    'под',
    'его',
    'она',
    'они',
    'оно',
    'так',
    'все',
    'всё',
    'уже',
    'ещё',
    'еще',
    'без',
    'про',
    'после',
    'перед',
    'когда',
    'где',
    'который',
  };

  FavoriteInterestProfile analyze(
    List<FavoriteItem> favorites, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final counts = <FavoriteCategory, int>{
      for (final category in FavoriteCategory.values) category: 0,
    };
    final weights = <String, double>{};

    for (final favorite in favorites) {
      counts[favorite.category] = (counts[favorite.category] ?? 0) + 1;
      final ageDays = reference.difference(favorite.addedAt).inDays;
      final recencyWeight = ageDays <= 30
          ? 1.0
          : ageDays <= 180
          ? 0.7
          : 0.4;

      // Explicit metadata (genres/topics/franchise) carries more signal than
      // generic words extracted from titles and descriptions.
      final explicit = _normalizeAll(favorite.interests);
      for (final interest in explicit) {
        weights.update(
          interest,
          (value) => value + 2.0 * recencyWeight,
          ifAbsent: () => 2.0 * recencyWeight,
        );
      }
      final titleTokens = _tokens(favorite.title);
      for (final token in titleTokens) {
        weights.update(
          token,
          (value) => value + 1.25 * recencyWeight,
          ifAbsent: () => 1.25 * recencyWeight,
        );
      }
      // Description is weak evidence to avoid generic blurbs dominating.
      for (final token in _tokens(favorite.description).take(24)) {
        weights.update(
          token,
          (value) => value + 0.2 * recencyWeight,
          ifAbsent: () => 0.2 * recencyWeight,
        );
      }
    }

    return FavoriteInterestProfile(
      categoryCounts: Map.unmodifiable(counts),
      interestWeights: Map.unmodifiable(weights),
      totalFavorites: favorites.length,
    );
  }

  /// Returns a positive, explainable ranking bonus for media metadata.
  double score(MediaItem item, FavoriteInterestProfile profile) {
    if (profile.totalFavorites == 0) return 0;
    final candidateTerms = <String>{
      ..._normalizeAll(item.categories),
      ..._tokens(item.title),
      ..._tokens(item.description),
    };
    var score = 0.0;
    for (final term in candidateTerms) {
      score += profile.interestWeights[term] ?? 0;
    }

    final category = _favoriteCategoryFor(item.type);
    if (category != null && profile.countFor(category) > 0) {
      // Category familiarity is intentionally a small boost, not a filter.
      score += 0.5;
    }
    return score;
  }

  Set<String> feedbackTermsFor(NewsArticle article) => {
    ..._normalizeAll(article.topics),
    ..._tokens(article.title),
  };

  /// Breaks a news score into the signals that affected its position.
  NewsScoreBreakdown explainNewsScore(
    NewsArticle article,
    FavoriteInterestProfile profile, {
    Set<String> lessInterested = const <String>{},
    Map<String, double> reactionWeights = const <String, double>{},
  }) {
    final candidateTerms = <String>{
      ..._normalizeAll(article.topics),
      ..._tokens(article.title),
      ..._tokens(article.summary),
      ..._tokens(article.channelName ?? ''),
    };
    var favoriteInterest = 0.0;
    var lessInterestedPenalty = 0.0;
    final favoriteInterestByTerm = <String, double>{};
    final lessInterestedTerms = <String>{};
    for (final term in candidateTerms) {
      final weight = profile.interestWeights[term] ?? 0;
      if (weight != 0) {
        favoriteInterestByTerm[term] = weight;
        favoriteInterest += weight;
      }
      if (lessInterested.contains(term)) {
        lessInterestedPenalty -= 4.0;
        lessInterestedTerms.add(term);
      }
    }

    var reaction = 0.0;
    final reactionByTopic = <String, double>{};
    for (final topic in article.topics) {
      final normalizedTopic = topic.trim().toLowerCase();
      final weight = reactionWeights[normalizedTopic] ?? 0;
      if (weight != 0) {
        reactionByTopic.update(
          normalizedTopic,
          (value) => value + weight,
          ifAbsent: () => weight,
        );
        reaction += weight;
      }
    }

    final trailerBonus =
        article.contentType == NewsContentType.trailer &&
            profile.countFor(FavoriteCategory.trailer) > 0
        ? 0.5
        : 0.0;
    final topicCategories = <String, FavoriteCategory>{
      'movie': FavoriteCategory.movie,
      'movies': FavoriteCategory.movie,
      'кино': FavoriteCategory.movie,
      'series': FavoriteCategory.series,
      'сериалы': FavoriteCategory.series,
      'anime': FavoriteCategory.anime,
      'аниме': FavoriteCategory.anime,
      'manga': FavoriteCategory.manga,
      'манга': FavoriteCategory.manga,
    };
    final familiarCategory = article.topics
        .map((topic) => topicCategories[topic.trim().toLowerCase()])
        .whereType<FavoriteCategory>()
        .any((category) => profile.countFor(category) > 0);

    return NewsScoreBreakdown(
      favoriteInterest: favoriteInterest,
      reaction: reaction,
      lessInterestedPenalty: lessInterestedPenalty,
      trailerBonus: trailerBonus,
      categoryBonus: familiarCategory ? 0.35 : 0.0,
      favoriteInterestByTerm: Map.unmodifiable(favoriteInterestByTerm),
      reactionByTopic: Map.unmodifiable(reactionByTopic),
      lessInterestedTerms: Set.unmodifiable(lessInterestedTerms),
    );
  }

  /// Ranks news and trailers using the same local favorites profile.
  /// It only reorders candidates; it never hides an article or makes network calls.
  double scoreNews(
    NewsArticle article,
    FavoriteInterestProfile profile, {
    Set<String> lessInterested = const <String>{},
    Map<String, double> reactionWeights = const <String, double>{},
  }) {
    if (profile.totalFavorites == 0 &&
        lessInterested.isEmpty &&
        reactionWeights.isEmpty) {
      return 0;
    }
    return explainNewsScore(
      article,
      profile,
      lessInterested: lessInterested,
      reactionWeights: reactionWeights,
    ).total;
  }

  List<NewsArticle> rankNews(
    List<NewsArticle> articles,
    FavoriteInterestProfile profile, {
    Set<String> lessInterested = const <String>{},
    Map<String, double> reactionWeights = const <String, double>{},
  }) {
    final indexed = articles.indexed.toList();
    indexed.sort((a, b) {
      final scoreComparison =
          scoreNews(
            b.$2,
            profile,
            lessInterested: lessInterested,
            reactionWeights: reactionWeights,
          ).compareTo(
            scoreNews(
              a.$2,
              profile,
              lessInterested: lessInterested,
              reactionWeights: reactionWeights,
            ),
          );
      return scoreComparison != 0 ? scoreComparison : a.$1.compareTo(b.$1);
    });
    return List<NewsArticle>.unmodifiable(indexed.map((entry) => entry.$2));
  }

  List<MediaItem> rank(List<MediaItem> items, FavoriteInterestProfile profile) {
    final indexed = items.indexed.toList();
    indexed.sort((a, b) {
      final scoreComparison = score(
        b.$2,
        profile,
      ).compareTo(score(a.$2, profile));
      return scoreComparison != 0 ? scoreComparison : a.$1.compareTo(b.$1);
    });
    return List<MediaItem>.unmodifiable(indexed.map((entry) => entry.$2));
  }

  Set<String> _normalizeAll(Iterable<String> values) => values
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.length >= 2 && !_stopWords.contains(value))
      .toSet();

  Set<String> _tokens(String value) {
    final matches = RegExp(
      r'[a-zа-яё0-9]{3,}',
      caseSensitive: false,
    ).allMatches(value.toLowerCase());
    return matches
        .map((match) => match.group(0)!)
        .where((token) => !_stopWords.contains(token))
        .toSet();
  }

  FavoriteCategory? _favoriteCategoryFor(String type) {
    return switch (type.trim().toLowerCase()) {
      'фильм' || 'фильмы' || 'movie' => FavoriteCategory.movie,
      'сериал' || 'сериалы' || 'series' => FavoriteCategory.series,
      'аниме' || 'anime' => FavoriteCategory.anime,
      'манга' || 'manga' => FavoriteCategory.manga,
      'трейлер' || 'трейлеры' || 'trailer' => FavoriteCategory.trailer,
      _ => null,
    };
  }
}
