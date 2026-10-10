import '../models/news_article.dart';

/// Decides whether a foreign article needs translation or can reuse an
/// already discovered Russian source.
///
/// This is intentionally a provider-agnostic foundation: the actual search
/// and AI adapters can be plugged in later without changing the news flow.
class SmartTranslationService {
  const SmartTranslationService();

  Future<LocalizedNewsResult> process(
    NewsArticle article, {
    NewsArticle? russianMatch,
  }) async {
    if (article.language.toLowerCase() == 'ru') {
      return LocalizedNewsResult(
        article: article,
        status: TranslationStatus.notNeeded,
      );
    }

    if (russianMatch != null) {
      return LocalizedNewsResult(
        article: russianMatch,
        originalArticle: article,
        status: TranslationStatus.foundRussianSource,
      );
    }

    return LocalizedNewsResult(
      article: article,
      status: TranslationStatus.needsTranslation,
    );
  }
}

enum TranslationStatus {
  notNeeded,
  foundRussianSource,
  needsTranslation,
  translatedByAi,
}

class LocalizedNewsResult {
  const LocalizedNewsResult({
    required this.article,
    required this.status,
    this.originalArticle,
  });

  final NewsArticle article;
  final NewsArticle? originalArticle;
  final TranslationStatus status;
}
