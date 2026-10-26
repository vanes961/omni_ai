import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/media/sources/kinopoisk_catalog_source.dart';
import 'package:omni_ai/features/media/sources/media_source.dart';

void main() {
  test('maps Kinopoisk metadata to a movie card using the API key header', () async {
    Uri? requestedUri;
    Map<String, String>? requestedHeaders;
    final source = KinopoiskCatalogSource(
      apiKey: 'test-api-key',
      client: MockClient((request) async {
        requestedUri = request.url;
        requestedHeaders = request.headers;
        return http.Response(
          jsonEncode({
            'docs': [
              {
                'id': 535341,
                'name': '1+1',
                'description': 'Французская комедия',
                'year': 2011,
                'type': 'movie',
                'poster': {'url': 'https://img.example/poster.jpg'},
                'rating': {'kp': 8.9, 'imdb': 8.5},
                'genres': [{'name': 'драма'}, {'name': 'комедия'}],
              },
              {
                'id': 77,
                'name': 'Сериал',
                'type': 'tv-series',
                'isSeries': true,
              },
              {'id': 78, 'name': '  '},
              'invalid',
            ],
          }),
          200,
        );
      }),
    );

    final items = await source.search('1+1', kind: MediaSourceKind.movie);

    expect(requestedUri?.host, 'api.poiskkino.dev');
    expect(requestedUri?.path, '/v1.5/movie/search');
    expect(requestedUri?.queryParameters['query'], '1+1');
    expect(requestedHeaders?['X-API-KEY'], 'test-api-key');
    expect(items, hasLength(1));
    expect(items.single.id, 'kinopoisk:535341');
    expect(items.single.title, '1+1');
    expect(items.single.type, 'Фильм');
    expect(items.single.posterUrl, 'https://img.example/poster.jpg');
    expect(items.single.rating, 8.9);
    expect(items.single.categories, containsAll(['драма', 'комедия', '2011']));
    expect(items.single.description, 'Французская комедия');
    expect(items.single.videoUrl, isEmpty);
  });

  test('filters search results to series when requested', () async {
    final source = KinopoiskCatalogSource(
      apiKey: 'test-api-key',
      client: MockClient((request) async => http.Response(
        jsonEncode({
          'docs': [
            {'id': 1, 'name': 'Film', 'type': 'movie'},
            {'id': 2, 'name': 'Series', 'type': 'tv-series'},
          ],
        }),
        200,
      )),
    );

    final items = await source.search('series', kind: MediaSourceKind.series);

    expect(items, hasLength(1));
    expect(items.single.id, 'kinopoisk:2');
    expect(items.single.type, 'Сериал');
  });

  test('does not make requests for blank queries, unsupported kinds or missing key', () async {
    var calls = 0;
    final source = KinopoiskCatalogSource(
      apiKey: '',
      client: MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );

    expect(await source.search('film', kind: MediaSourceKind.movie), isEmpty);
    expect(await source.search(' ', kind: MediaSourceKind.movie), isEmpty);
    expect(await source.search('film', kind: MediaSourceKind.anime), isEmpty);
    expect(calls, 0);
  });

  test('throws a safe error for non-success responses', () async {
    final source = KinopoiskCatalogSource(
      apiKey: 'secret-token',
      client: MockClient((request) async => http.Response('denied', 401)),
    );

    expect(
      () => source.search('film', kind: MediaSourceKind.movie),
      throwsA(
        isA<CatalogHttpException>().having(
          (error) => error.toString(),
          'message',
          contains('401'),
        ),
      ),
    );
  });

  test('rejects non-http poster URLs', () async {
    final source = KinopoiskCatalogSource(
      apiKey: 'test-api-key',
      client: MockClient((request) async => http.Response(
        jsonEncode({
          'docs': [
            {
              'id': 1,
              'name': 'Film',
              'type': 'movie',
              'poster': {'url': 'file:///private/poster.jpg'},
            },
          ],
        }),
        200,
      )),
    );

    final items = await source.search('film', kind: MediaSourceKind.movie);

    expect(items.single.posterUrl, isEmpty);
  });
}
