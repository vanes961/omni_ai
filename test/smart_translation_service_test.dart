import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/news/models/news_article.dart';
import 'package:omni_ai/features/news/services/smart_translation_service.dart';

void main() {
  const service = SmartTranslationService();

  test('does not request translation for a Russian article', () async {
    final article = _article(language: 'ru');

    final result = await service.process(article);

    expect(result.status, TranslationStatus.notNeeded);
    expect(result.article, same(article));
    expect(result.originalArticle, isNull);
  });

  test('reuses a Russian match and preserves the foreign original', () async {
    final original = _article(language: 'en', id: 'original');
    final russian = _article(language: 'ru', id: 'russian');

    final result = await service.process(original, russianMatch: russian);

    expect(result.status, TranslationStatus.foundRussianSource);
    expect(result.article, same(russian));
    expect(result.originalArticle, same(original));
  });

  test('finds a Russian source from provided candidates', () async {
    final original = _article(
      language: 'en',
      id: 'original',
      title: 'Nintendo Switch 2 release date revealed',
    );
    final russian = _article(
      language: 'ru',
      id: 'russian',
      title: 'Раскрыта дата выхода Nintendo Switch 2',
    );

    final result = await service.process(
      original,
      russianCandidates: [russian],
    );

    expect(result.status, TranslationStatus.foundRussianSource);
    expect(result.article, same(russian));
    expect(result.originalArticle, same(original));
  });

  test('requests translation when no Russian match is available', () async {
    final original = _article(language: 'en');

    final result = await service.process(original);

    expect(result.status, TranslationStatus.needsTranslation);
    expect(result.article, same(original));
    expect(result.originalArticle, isNull);
  });

  test('does not accept a non-Russian candidate as a Russian match', () async {
    final original = _article(language: 'en', id: 'original');
    final incorrectCandidate = _article(language: 'de', id: 'candidate');

    final result = await service.process(
      original,
      russianMatch: incorrectCandidate,
    );

    expect(result.status, TranslationStatus.needsTranslation);
    expect(result.article, same(original));
    expect(result.originalArticle, isNull);
  });
}

NewsArticle _article({
  String id = 'news-1',
  required String language,
  String title = 'Example headline',
}) {
  return NewsArticle(
    id: id,
    title: title,
    summary: 'Example summary',
    sourceName: 'Example source',
    sourceUrl: 'https://example.com/$id',
    publishedAt: DateTime.utc(2026, 10, 10),
    topics: const ['technology'],
    language: language,
  );
}
