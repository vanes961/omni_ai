import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/news/models/news_article.dart';
import 'package:omni_ai/features/news/services/news_source_localization_service.dart';

void main() {
  const service = NewsSourceLocalizationService();

  test('keeps Russian match and suppresses the matching foreign duplicate', () async {
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

  test('retains foreign articles without a reliable Russian match', () async {
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

  test('does not suppress Russian articles during processing', () async {
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
  );
}
