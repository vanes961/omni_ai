import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/services/manga_chapter_service.dart';

void main() {
  test('only exposes Russian-translated chapters and skips duplicates', () {
    final chapters = MangaChapterService.parseRussianChapters({
      'data': [
        {
          'id': 'ru-1',
          'attributes': {
            'translatedLanguage': 'ru',
            'chapter': '12.5',
            'title': 'Промежуточная глава',
            'pages': 28,
            'volume': '2',
            'publishAt': '2025-01-02T10:00:00+00:00',
          },
        },
        {
          'id': 'en-1',
          'attributes': {
            'translatedLanguage': 'en',
            'chapter': '13',
            'title': 'English chapter',
            'pages': 20,
          },
        },
        {
          'id': 'ru-1',
          'attributes': {
            'translatedLanguage': 'ru',
            'chapter': 'duplicate',
            'pages': 10,
          },
        },
        {
          'id': 'ru-2',
          'attributes': {
            'translatedLanguage': 'ru',
            'chapter': null,
            'title': null,
            'pages': 0,
          },
        },
      ],
    }, mangaId: 'manga-1');

    expect(chapters, hasLength(2));
    expect(chapters.first.id, 'ru-1');
    expect(chapters.first.language, 'ru');
    expect(chapters.first.chapter, '12.5');
    expect(chapters.first.title, 'Промежуточная глава');
    expect(chapters.first.pageCount, 28);
    expect(chapters.first.volume, '2');
    expect(chapters.first.publishedAt, DateTime.utc(2025, 1, 2, 10));
    expect(chapters.last.displayLabel, 'Без номера');
  });

  test('rejects malformed chapter payloads', () {
    expect(
      MangaChapterService.parseRussianChapters(null, mangaId: 'm'),
      isEmpty,
    );
    expect(
      MangaChapterService.parseRussianChapters({'data': 'bad'}, mangaId: 'm'),
      isEmpty,
    );
  });

  test('parses MangaDex page manifest and builds secure image URLs', () {
    final pages = MangaChapterPageSet.parse({
      'baseUrl': 'https://uploads.mangadex.org',
      'chapter': {
        'hash': 'safe-hash',
        'data': ['001.jpg', '002.webp'],
        'dataSaver': ['001.jpg'],
      },
    }, chapterId: 'chapter-1');

    expect(pages, isNotNull);
    expect(pages!.imageUrls, hasLength(2));
    expect(
      pages.imageUrls.first.toString(),
      'https://uploads.mangadex.org/data/safe-hash/001.jpg',
    );
    expect(pages.urls(dataSaver: true), hasLength(1));
  });

  test('rejects untrusted CDN and malformed filenames', () {
    expect(
      MangaChapterPageSet.parse({
        'baseUrl': 'http://uploads.mangadex.org',
        'chapter': {'hash': 'h', 'data': ['001.jpg'], 'dataSaver': ['001.jpg']},
      }, chapterId: 'ch'),
      isNull,
    );
    expect(
      MangaChapterPageSet.parse({
        'baseUrl': 'https://uploads.mangadex.org',
        'chapter': {
          'hash': 'h',
          'data': ['../secret.jpg'],
          'dataSaver': ['001.jpg'],
        },
      }, chapterId: 'ch'),
      isNull,
    );
  });
}
