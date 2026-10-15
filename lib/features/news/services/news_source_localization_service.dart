import 'dart:async';
import 'dart:convert';

import 'package:omni_ai/core/ai_engine/models/ai_error.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';

import '../models/news_article.dart';
import 'smart_translation_service.dart';

/// Reuses a matching Russian source and translates unmatched foreign excerpts
/// when an AI engine is available. Translation failures never remove stories.
class NewsSourceLocalizationService {
  const NewsSourceLocalizationService({
    this.aiEngine,
    this.maxAiTranslationsPerBatch = 2,
    this.translationTimeout = const Duration(seconds: 8),
    this._translationService = const SmartTranslationService(),
  }) : assert(maxAiTranslationsPerBatch >= 0);

  final AIEngine? aiEngine;

  /// Limits sequential cloud/local model calls during one feed refresh.
  final int maxAiTranslationsPerBatch;
  final Duration translationTimeout;
  final SmartTranslationService _translationService;

  Future<List<NewsArticle>> localizeCandidates(
    Iterable<NewsArticle> candidates,
  ) async {
    final report = await localizeCandidatesWithReport(candidates);
    return report.articles;
  }

  Future<NewsLocalizationResult> localizeCandidatesWithReport(
    Iterable<NewsArticle> candidates,
  ) async {
    final articles = candidates.toList(growable: false);
    final russianCandidates = articles
        .where((article) => article.language.toLowerCase() == 'ru')
        .toList(growable: false);
    final result = <NewsArticle>[];
    var translationAttempts = 0;
    var translatedCount = 0;
    var duplicateSuppressedCount = 0;
    var budgetSkippedCount = 0;
    var translationFailureCount = 0;
    final failureReasonCounts = <NewsTranslationFailureReason, int>{};
    var foreignUntranslatedCount = 0;

    for (final article in articles) {
      // Video and trailer cards are metadata previews, not article bodies.
      // Keep their original title, description and outbound link without
      // duplicate matching or an AI translation request.
      if (article.contentType != NewsContentType.article) {
        result.add(article);
        continue;
      }

      final localized = await _translationService.process(
        article,
        russianCandidates: russianCandidates,
      );
      if (article.language.toLowerCase() == 'ru') {
        result.add(article);
      } else if (localized.status == TranslationStatus.foundRussianSource) {
        // Keep the Russian candidate already present in the input collection;
        // suppress only the foreign duplicate.
        duplicateSuppressedCount++;
      } else if (aiEngine != null &&
          translationAttempts < maxAiTranslationsPerBatch) {
        translationAttempts++;
        final translation = await _translateIfAvailable(article);
        result.add(translation.article);
        if (translation.translated) {
          translatedCount++;
        } else {
          translationFailureCount++;
          final reason = translation.failureReason ?? NewsTranslationFailureReason.unknown;
          failureReasonCounts.update(reason, (count) => count + 1, ifAbsent: () => 1);
          foreignUntranslatedCount++;
        }
      } else {
        // Keep the source visible when the per-refresh translation budget is
        // exhausted or no AI engine is configured.
        result.add(article);
        foreignUntranslatedCount++;
        if (aiEngine != null) {
          budgetSkippedCount++;
        }
      }
    }

    return NewsLocalizationResult(
      articles: List<NewsArticle>.unmodifiable(result),
      translatedCount: translatedCount,
      duplicateSuppressedCount: duplicateSuppressedCount,
      budgetSkippedCount: budgetSkippedCount,
      translationFailureCount: translationFailureCount,
      failureReasonCounts: Map<NewsTranslationFailureReason, int>.unmodifiable(failureReasonCounts),
      foreignUntranslatedCount: foreignUntranslatedCount,
    );
  }

  Future<_TranslationAttempt> _translateIfAvailable(NewsArticle article) async {
    final engine = aiEngine;
    if (engine == null) return _TranslationAttempt(article, false);
    final cancellationToken = AICancellationToken();
    try {
      final response = await engine
          .execute(
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
            cancellationToken: cancellationToken,
          )
          .timeout(
            translationTimeout,
            onTimeout: () {
              cancellationToken.cancel();
              throw TimeoutException('News translation timed out.');
            },
          );
      final decoded = jsonDecode(response.text);
      if (decoded is! Map<String, dynamic>) {
        return _TranslationAttempt(article, false, NewsTranslationFailureReason.invalidOutput);
      }
      final title = decoded['title'];
      final summary = decoded['summary'];
      if (title is! String || title.trim().isEmpty || summary is! String) {
        return _TranslationAttempt(article, false, NewsTranslationFailureReason.invalidOutput);
      }
      return _TranslationAttempt(
        NewsArticle(
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
        ),
        true,
      );
    } on FormatException {
      return _TranslationAttempt(
        article,
        false,
        NewsTranslationFailureReason.malformedResponse,
      );
    } on TimeoutException {
      return _TranslationAttempt(article, false, NewsTranslationFailureReason.timeout);
    } on AIEngineException catch (error) {
      return _TranslationAttempt(
        article,
        false,
        switch (error.error.code) {
          AIErrorCode.configuration => NewsTranslationFailureReason.configuration,
          AIErrorCode.unauthorized => NewsTranslationFailureReason.unauthorized,
          AIErrorCode.rateLimited => NewsTranslationFailureReason.rateLimited,
          AIErrorCode.providerUnavailable => NewsTranslationFailureReason.providerUnavailable,
          AIErrorCode.timeout => NewsTranslationFailureReason.timeout,
          AIErrorCode.malformedResponse => NewsTranslationFailureReason.malformedResponse,
          AIErrorCode.cancelled => NewsTranslationFailureReason.cancelled,
          _ => NewsTranslationFailureReason.provider,
        },
      );
    } catch (_) {
      // Keep the original source card visible if translation fails.
      return _TranslationAttempt(article, false, NewsTranslationFailureReason.unknown);
    }
  }
}

enum NewsTranslationFailureReason {
  configuration,
  unauthorized,
  rateLimited,
  providerUnavailable,
  timeout,
  malformedResponse,
  invalidOutput,
  cancelled,
  provider,
  unknown,
}

class NewsLocalizationResult {
  const NewsLocalizationResult({
    required this.articles,
    required this.translatedCount,
    required this.duplicateSuppressedCount,
    required this.budgetSkippedCount,
    required this.translationFailureCount,
    required this.failureReasonCounts,
    required this.foreignUntranslatedCount,
  });

  final List<NewsArticle> articles;
  final int translatedCount;
  final int duplicateSuppressedCount;
  final int budgetSkippedCount;
  final int translationFailureCount;
  final Map<NewsTranslationFailureReason, int> failureReasonCounts;
  final int foreignUntranslatedCount;
}

class _TranslationAttempt {
  const _TranslationAttempt(this.article, this.translated, [this.failureReason]);

  final NewsArticle article;
  final bool translated;
  final NewsTranslationFailureReason? failureReason;
}
