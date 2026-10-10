import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/news/models/news_article.dart';
import 'package:omni_ai/features/news/services/russian_source_matcher.dart';

void main() {
  const matcher = RussianSourceMatcher();

  test('matches a Russian headline with shared distinctive entities', () {
    final foreign = _article(
      id: 'en',
      language: 'en',
      title: 'Nintendo Switch 2 release date revealed',
      publishedAt: DateTime.utc(2026, 10, 10, 12),
    );
    final russian = _article(
      id: 'ru',
      language: 'ru',
      title: 'Раскрыта дата выхода Nintendo Switch 2',
      publishedAt: DateTime.utc(2026, 10, 10, 14),
    );

    final match = matcher.findBestMatch(foreign, [russian]);

    expect(match?.article, same(russian));
    expect(match!.score, greaterThan(0));
  });

  test('rejects a candidate in a non-Russian language', () {
    final foreign = _article(id: 'en', language: 'en');
    final german = _article(
      id: 'de',
      language: 'de',
      title: 'Nintendo Switch 2 release date revealed',
    );

    expect(matcher.findBestMatch(foreign, [german]), isNull);
  });

  test('rejects unrelated headlines even when topics match', () {
    final foreign = _article(
      id: 'en',
      language: 'en',
      title: 'Nintendo announces a new console',
    );
    final russian = _article(
      id: 'ru',
      language: 'ru',
      title: 'Valve reveals new handheld gaming device',
    );

    expect(matcher.findBestMatch(foreign, [russian]), isNull);
  });

  test('rejects candidates outside the publication window', () {
    final foreign = _article(
      id: 'en',
      language: 'en',
      title: 'Nintendo Switch 2 release date revealed',
      publishedAt: DateTime.utc(2026, 10, 10),
    );
    final russian = _article(
      id: 'ru',
      language: 'ru',
      title: 'Nintendo Switch 2: названа дата выхода',
      publishedAt: DateTime.utc(2026, 10, 20),
    );

    expect(matcher.findBestMatch(foreign, [russian]), isNull);
  });

  test('prefers the closest publication time for comparable matches', () {
    final foreign = _article(
      id: 'en',
      language: 'en',
      title: 'Nintendo Switch 2 release date revealed',
      publishedAt: DateTime.utc(2026, 10, 10, 12),
    );
    final older = _article(
      id: 'ru-old',
      language: 'ru',
      title: 'Nintendo Switch 2: дата выхода раскрыта',
      publishedAt: DateTime.utc(2026, 10, 9),
    );
    final closer = _article(
      id: 'ru-close',
      language: 'ru',
      title: 'Nintendo Switch 2 — раскрыта дата выхода',
      publishedAt: DateTime.utc(2026, 10, 10, 11),
    );

    final match = matcher.findBestMatch(foreign, [older, closer]);

    expect(match?.article, same(closer));
  });
}

NewsArticle _article({
  required String id,
  required String language,
  String title = 'Nintendo Switch 2 release date revealed',
  DateTime? publishedAt,
  List<String> topics = const ['games'],
}) {
  return NewsArticle(
    id: id,
    title: title,
    summary: '',
    sourceName: 'Source $id',
    sourceUrl: 'https://example.com/$id',
    publishedAt: publishedAt ?? DateTime.utc(2026, 10, 10, 12),
    topics: topics,
    language: language,
  );
}
