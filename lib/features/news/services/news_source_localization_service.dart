import 'dart:convert';

import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';

import '../models/news_article.dart';
import 'smart_translation_service.dart';

/// Reuses a matching Russian source and translates unmatched foreign excerpts
/// when an AI engine is available. Translation failures never remove stories.
class NewsSourceLocalizationService {
  const NewsSourceLocalizationService({
    this.aiEngine,
    this._translationService = const SmartTranslationService(),
  });

  final AIEngine? aiEngine;
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
      if (article.language.toLowerCase() == 'ru') {
        result.add(article);
      } else if (localized.status == TranslationStatus.foundRussianSource) {
        // Keep the Russian candidate already present in the input collection;
        // suppress only the foreign duplicate.
        continue;
      } else {
        result.add(await _translateIfAvailable(article));
      }
    }

    return List<NewsArticle>.unmodifiable(result);
  }

  Future<NewsArticle> _translateIfAvailable(NewsArticle article) async {
    final engine = aiEngine;
    if (engine == null) return article;
    try {
      final response = await engine.execute(
        AIRequest(
          id: 'news-translation-${DateTime.now().microsecondsSinceEpoch}',
          systemInstruction:
              'Translate news text into natural Russian. Preserve names, '
              'numbers, factual meaning, and uncertainty. Do not add facts. '
              'Return only a valid JSON object with string fields "title" '
              'and "summary". Translate only the supplied text.',
          prompt: jsonEncode({
            'title': article.title,
            'summary': article.summary,
          }),
          metadata: const {'feature': 'news_translation'},
        ),
      );
      final decoded = jsonDecode(response.text);
      if (decoded is! Map<String, dynamic>) return article;
      final title = decoded['title'];
      final summary = decoded['summary'];
      if (title is! String || title.trim().isEmpty ||
          summary is! String) {
        return article;
      }
      return NewsArticle(
        id: article.id,
        title: title.trim(),
        summary: summary.trim(),
        sourceName: article.sourceName,
        sourceUrl: article.sourceUrl,
        publishedAt: article.publishedAt,
        topics: article.topics,
        language: 'ru',
        region: article.region,
        isCritical: article.isCritical,
        isVerified: article.isVerified,
        contentType: article.contentType,
        videoUrl: article.videoUrl,
        thumbnailUrl: article.thumbnailUrl,
        channelName: article.channelName,
        releaseDate: article.releaseDate,
        releaseDateSourceUrl: article.releaseDateSourceUrl,
      );
    } catch (_) {
      // A translation provider can be offline or return malformed output.
      // Keep the original source card visible rather than failing the feed.
      return article;
    }
  }
}
