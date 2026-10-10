import '../models/news_article.dart';

/// Decides whether a foreign article needs translation or can reuse an
/// already discovered Russian source.
///
/// The caller is responsible for finding candidate matches. This service
/// validates the candidate language and chooses the next processing status;
/// it does not claim to perform web search or translation itself.
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

    if (russianMatch != null &&
        russianMatch.language.toLowerCase() == 'ru') {
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
