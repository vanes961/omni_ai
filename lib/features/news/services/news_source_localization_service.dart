import '../models/news_article.dart';
import 'smart_translation_service.dart';

/// Removes a foreign feed entry only when a matching Russian candidate is
/// already present. Unmatched foreign articles remain available to the feed.
class NewsSourceLocalizationService {
  const NewsSourceLocalizationService({
    SmartTranslationService translationService =
        const SmartTranslationService(),
  }) : _translationService = translationService;

  final SmartTranslationService _translationService;

  Future<List<NewsArticle>> localizeCandidates(
    Iterable<NewsArticle> candidates,
  ) async {
    final articles = candidates.toList(growable: false);
    final russianCandidates = articles
        .where((article) => article.language.toLowerCase() == 'ru')
        .toList(growable: false);
    final result = <NewsArticle>[];

    for (final article in articles) {
      final localized = await _translationService.process(
        article,
        russianCandidates: russianCandidates,
      );
      if (article.language.toLowerCase() == 'ru' ||
          localized.status != TranslationStatus.foundRussianSource) {
        result.add(article);
      }
    }

    return List<NewsArticle>.unmodifiable(result);
  }
}
