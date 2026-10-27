import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/media/services/manga_catalog_service.dart';

void main() {
  test('parses MangaDex search results with localized titles and cover art', () {
    final items = MangaCatalogService.parseSearchResponse({
      'data': [
        {
          'id': 'abc-123',
          'attributes': {
            'title': {'en': 'Example Manga', 'ja-ro': 'Rei'},
            'description': {'en': 'English description', 'ru': 'Описание'},
            'status': 'completed',
            'year': 2022,
            'links': {'al': '12345'},
          },
          'relationships': [
            {
              'id': 'cover-1',
              'type': 'cover_art',
              'attributes': {'fileName': 'cover-file.jpg'},
            },
          ],
        },
      ],
    });

    expect(items, hasLength(1));
    expect(items.single.id, 'abc-123');
    expect(items.single.canonicalId, 'mangadex:abc-123');
    expect(items.single.title, 'Example Manga');
    expect(items.single.description, 'Описание');
    expect(items.single.status, 'completed');
    expect(items.single.year, 2022);
    expect(items.single.anilistId, 12345);
    expect(
      items.single.coverUrl,
      'https://uploads.mangadex.org/covers/abc-123/cover-file.jpg.256.jpg',
    );
    expect(items.single.sourceUrl, 'https://mangadex.org/title/abc-123');
  });

  test('ignores malformed entries and duplicate IDs', () {
    final items = MangaCatalogService.parseSearchResponse({
      'data': [
        null,
        {'id': 'missing-attributes'},
        {
          'id': 'duplicate',
          'attributes': {'title': {'en': 'First'}},
          'relationships': [],
        },
        {
          'id': 'duplicate',
          'attributes': {'title': {'en': 'Second'}},
          'relationships': [],
        },
        {
          'id': 'empty-title',
          'attributes': {'title': {}},
          'relationships': [],
        },
      ],
    });

    expect(items, hasLength(1));
    expect(items.single.title, 'First');
  });

  test('prefers Russian description and safely handles absent metadata', () {
    final items = MangaCatalogService.parseSearchResponse({
      'data': [
        {
          'id': 'minimal',
          'attributes': {
            'title': {'ru': 'Манга'},
          },
          'relationships': [],
        },
      ],
    });

    expect(items.single.title, 'Манга');
    expect(items.single.description, isEmpty);
    expect(items.single.coverUrl, isEmpty);
    expect(items.single.authors, isEmpty);
    expect(items.single.year, isNull);
    expect(items.single.anilistId, isNull);
  });

  test('returns empty for invalid top-level payloads', () {
    expect(MangaCatalogService.parseSearchResponse(null), isEmpty);
    expect(MangaCatalogService.parseSearchResponse({'data': 'wrong'}), isEmpty);
  });

  test('returns empty results for a valid empty MangaDex response', () async {
    final service = MangaCatalogService(
      client: MockClient((_) async => http.Response(jsonEncode({'data': []}), 200)),
    );
    expect(await service.search('no such manga'), isEmpty);
    service.close();
  });

  test('keeps search resilient when MangaDex returns a non-success response', () async {
    final service = MangaCatalogService(
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );
    expect(await service.search('Berserk'), isEmpty);
    service.close();
  });

  test('keeps search resilient when the primary source is offline', () async {
    final service = MangaCatalogService(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(await service.search('Berserk'), isEmpty);
    service.close();
  });
}
