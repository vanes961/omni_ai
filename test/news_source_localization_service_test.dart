import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:omni_ai/features/news/models/news_article.dart';
import 'package:omni_ai/features/news/services/news_source_localization_service.dart';

void main() {
  const service = NewsSourceLocalizationService();

  test('suppresses matching foreign duplicates', () async {
    final foreign = _article(
      id: 'foreign',
      language: 'en',
      title: 'Nintendo Switch 2 release date revealed',
    );
    final russian = _article(
      id: 'russian',
      language: 'ru',
      title: 'Раскрыта дата выхода Nintendo Switch 2',
    );

    final result = await service.localizeCandidates([foreign, russian]);

    expect(result, hasLength(1));
    expect(result.single, same(russian));
  });

  test('keeps unmatched foreign articles', () async {
    final foreign = _article(
      id: 'foreign',
      language: 'en',
      title: 'Nintendo announces a new console',
    );
    final russian = _article(
      id: 'russian',
      language: 'ru',
      title: 'Valve reveals a handheld gaming device',
    );

    final result = await service.localizeCandidates([foreign, russian]);

    expect(result, hasLength(2));
    expect(result, contains(foreign));
    expect(result, contains(russian));
  });

  test('translates unmatched foreign articles with AI', () async {
    final foreign = _article(
      id: 'foreign',
      language: 'en',
      title: 'A new console is announced',
    );
    final translationService = NewsSourceLocalizationService(
      aiEngine: AIEngine(provider: _TranslationProvider()),
    );

    final result = await translationService.localizeCandidates([foreign]);

    expect(result, hasLength(1));
    expect(result.single.title, 'Консоль');
    expect(result.single.summary, 'Описание');
    expect(result.single.language, 'ru');
    expect(result.single.sourceUrl, foreign.sourceUrl);
    expect(result.single.id, foreign.id);
  });

  test(
    'limits AI translations per refresh and keeps remaining sources',
    () async {
      final provider = _TranslationProvider();
      final translationService = NewsSourceLocalizationService(
        aiEngine: AIEngine(provider: provider),
        maxAiTranslationsPerBatch: 1,
      );
      final first = _article(
        id: 'first',
        language: 'en',
        title: 'First foreign headline',
      );
      final second = _article(
        id: 'second',
        language: 'en',
        title: 'Second foreign headline',
      );

      final result = await translationService.localizeCandidates([
        first,
        second,
      ]);

      expect(provider.calls, 1);
      expect(result, hasLength(2));
      expect(result.first.language, 'ru');
      expect(result.last, same(second));
    },
  );

  test(
    'keeps the original article when AI translation times out',
    () async {
      final foreign = _article(
        id: 'slow',
        language: 'en',
        title: 'Slow foreign headline',
      );
      final provider = _TranslationProvider(
        delay: const Duration(milliseconds: 50),
      );
      final engine = AIEngine(provider: provider);
      final translationService = NewsSourceLocalizationService(
        aiEngine: engine,
        translationTimeout: const Duration(milliseconds: 1),
      );

      final report = await translationService.localizeCandidatesWithReport([foreign]);

      expect(report.articles, hasLength(1));
      expect(report.articles.single, same(foreign));
      expect(report.translationFailureCount, 1);
      expect(
        report.failureReasonCounts[NewsTranslationFailureReason.timeout],
        1,
      );
    },
  );

  test('reports malformed AI translation output', () async {
    final foreign = _article(
      id: 'malformed',
      language: 'en',
      title: 'Foreign headline',
    );
    final translationService = NewsSourceLocalizationService(
      aiEngine: AIEngine(
        provider: _TranslationProvider(responseText: 'not-json'),
      ),
    );

    final report = await translationService.localizeCandidatesWithReport([
      foreign,
    ]);

    expect(report.articles.single, same(foreign));
    expect(report.translationFailureCount, 1);
    expect(
      report.failureReasonCounts[NewsTranslationFailureReason.malformedResponse],
      1,
    );
  });

  test('does not send video or trailer previews to AI localization', () async {
    final provider = _TranslationProvider();
    final translationService = NewsSourceLocalizationService(
      aiEngine: AIEngine(provider: provider),
    );
    final video = _article(
      id: 'video',
      language: 'en',
      title: 'New video announcement',
      contentType: NewsContentType.video,
      videoUrl: 'https://youtube.com/watch?v=video',
    );
    final trailer = _article(
      id: 'trailer',
      language: 'en',
      title: 'New film trailer',
      contentType: NewsContentType.trailer,
      videoUrl: 'https://youtube.com/watch?v=trailer',
    );

    final result = await translationService.localizeCandidates([video, trailer]);

    expect(provider.calls, 0);
    expect(result, hasLength(2));
    expect(result[0], same(video));
    expect(result[1], same(trailer));
    expect(result[0].videoUrl, 'https://youtube.com/watch?v=video');
    expect(result[1].videoUrl, 'https://youtube.com/watch?v=trailer');
  });

  test('reports translation outcomes and budget skips', () async {
    final duplicate = _article(
      id: 'duplicate',
      language: 'en',
      title: 'Nintendo Switch 2 release date revealed',
    );
    final russian = _article(
      id: 'russian',
      language: 'ru',
      title: 'Раскрыта дата выхода Nintendo Switch 2',
    );
    final translated = _article(
      id: 'translated',
      language: 'en',
      title: 'A new console is announced',
    );
    final skipped = _article(
      id: 'skipped',
      language: 'en',
      title: 'A new game is announced',
    );
    final serviceWithLimit = NewsSourceLocalizationService(
      aiEngine: AIEngine(provider: _TranslationProvider()),
      maxAiTranslationsPerBatch: 1,
    );

    final report = await serviceWithLimit.localizeCandidatesWithReport([
      duplicate,
      russian,
      translated,
      skipped,
    ]);

    expect(report.articles, hasLength(3));
    expect(report.articles, contains(russian));
    expect(report.articles, contains(skipped));
    expect(report.duplicateSuppressedCount, 1);
    expect(report.translatedCount, 1);
    expect(report.budgetSkippedCount, 1);
    expect(report.translationFailureCount, 0);
    expect(report.foreignUntranslatedCount, 1);
  });

  test('keeps Russian articles', () async {
    final russian = _article(
      id: 'russian',
      language: 'ru',
      title: 'Локальная новость без иностранного оригинала',
    );

    final result = await service.localizeCandidates([russian]);

    expect(result, hasLength(1));
    expect(result.single, same(russian));
  });
}

NewsArticle _article({
  required String id,
  required String language,
  required String title,
  NewsContentType contentType = NewsContentType.article,
  String? videoUrl,
}) {
  return NewsArticle(
    id: id,
    title: title,
    summary: '',
    sourceName: 'Source $id',
    sourceUrl: 'https://example.com/$id',
    publishedAt: DateTime.utc(2026, 10, 10, 12),
    topics: const ['games'],
    language: language,
    contentType: contentType,
    videoUrl: videoUrl,
  );
}

class _TranslationProvider implements AIProvider {
  _TranslationProvider({
    this.delay = Duration.zero,
    this.responseText = '{"title":"Консоль","summary":"Описание"}',
  });

  final Duration delay;
  final String responseText;
  int calls = 0;

  @override
  String get id => 'test-translation';

  @override
  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  }) async {
    calls++;
    await Future<void>.delayed(delay);
    return AIResponse(
      requestId: request.id,
      text: responseText,
      providerId: id,
      generatedAt: DateTime.utc(2026, 10, 12),
    );
  }
}
