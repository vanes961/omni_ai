import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/media/sources/media_source.dart';
import 'package:omni_ai/features/media/sources/public_catalog_sources.dart';

void main() {
  test('Jikan searches anime and maps a real catalog record', () async {
    Uri? requested;
    final source = JikanCatalogSource(client: MockClient((request) async {
      requested = request.url;
      return http.Response(jsonEncode({
        'data': [
          {
            'mal_id': 11,
            'title': 'Example',
            'title_english': 'Example Anime',
            'synopsis': '<p>Story <b>text</b></p>',
            'score': 8.1,
            'images': {'jpg': {'large_image_url': 'https://img.example/poster.jpg'}},
            'genres': [{'name': 'Drama'}],
            'year': 2025,
          }
        ]
      }), 200);
    }));

    final items = await source.search('example', kind: MediaSourceKind.anime);
    expect(requested?.host, 'api.jikan.moe');
    expect(requested?.path, '/v4/anime');
    expect(items, hasLength(1));
    expect(items.single.id, 'jikan:11');
    expect(items.single.title, 'Example Anime');
    expect(items.single.type, 'Аниме');
    expect(items.single.posterUrl, 'https://img.example/poster.jpg');
    expect(items.single.description, 'Story text');
    expect(items.single.videoUrl, isEmpty);
  });

  test('AniList maps public GraphQL metadata without inventing streams', () async {
    Uri? requested;
    final source = AniListCatalogSource(client: MockClient((request) async {
      requested = request.url;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['variables']['type'], 'MANGA');
      return http.Response(jsonEncode({
        'data': {
          'Page': {
            'media': [
              {
                'id': 22,
                'title': {'english': 'Manga Title', 'romaji': 'Manga Title'},
                'description': '<i>Summary</i>',
                'averageScore': 85,
                'genres': ['Fantasy'],
                'seasonYear': 2024,
                'coverImage': {'large': 'https://img.example/manga.jpg'},
              }
            ]
          }
        }
      }), 200);
    }));

    final items = await source.search('manga', kind: MediaSourceKind.manga);
    expect(requested?.host, 'graphql.anilist.co');
    expect(items, hasLength(1));
    expect(items.single.id, 'anilist:manga:22');
    expect(items.single.type, 'Манга');
    expect(items.single.rating, 8.5);
    expect(items.single.videoUrl, isEmpty);
  });

  test('Kitsu accepts JSON:API records and ignores invalid image URLs', () async {
    final source = KitsuCatalogSource(client: MockClient((request) async {
      expect(request.url.path, '/api/edge/anime');
      return http.Response(jsonEncode({
        'data': [
          {
            'id': '44',
            'attributes': {
              'canonicalTitle': 'Kitsu Anime',
              'averageRating': '81.2',
              'startDate': '2023-04-01',
              'synopsis': 'Synopsis',
              'posterImage': {'large': 'javascript:alert(1)'},
            }
          }
        ]
      }), 200);
    }));

    final items = await source.search('kitsu', kind: MediaSourceKind.anime);
    expect(items, hasLength(1));
    expect(items.single.id, 'kitsu:anime:44');
    expect(items.single.rating, closeTo(8.12, 0.001));
    expect(items.single.posterUrl, isEmpty);
    expect(items.single.videoUrl, isEmpty);
  });

  test('keyed and unsupported sources do not make unnecessary requests', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 200);
    });
    final omdb = OmdbCatalogSource(apiKey: '', client: client);
    expect(await omdb.search('film', kind: MediaSourceKind.movie), isEmpty);
    expect(await JikanCatalogSource(client: client).search(' ', kind: MediaSourceKind.manga), isEmpty);
    expect(calls, 0);
  });
}
