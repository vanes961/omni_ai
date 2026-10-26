import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/media/sources/anilibria_catalog_source.dart';
import 'package:omni_ai/features/media/sources/media_source.dart';

void main() {
  test('searches the Russian catalog and maps a title to a media card', () async {
    Uri? requestedUri;
    final source = AniLibriaCatalogSource(
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response.bytes(
          utf8.encode(jsonEncode([
            {
              'id': 123,
              'name': {'main': 'Пример аниме', 'english': 'Example Anime'},
              'poster': {'preview': 'https://img.example/poster.jpg'},
              'genres': [
                {'name': 'Приключения'},
                {'name': 'Фантастика'},
              ],
              'description': '<p>Описание <b>аниме</b></p>',
              'year': 2025,
              'rating': {'average': 8.2},
            },
            {'id': 124, 'name': {'main': '   '}},
            'invalid',
          ])),
          200,
        );
      }),
    );

    final items = await source.search('пример', kind: MediaSourceKind.anime);

    expect(requestedUri?.host, 'api.anilibria.app');
    expect(requestedUri?.path, '/api/v1/app/search/releases');
    expect(requestedUri?.queryParameters['query'], 'пример');
    expect(items, hasLength(1));
    expect(items.single.id, 'anilibria:123');
    expect(items.single.title, 'Пример аниме');
    expect(items.single.type, 'Аниме');
    expect(items.single.posterUrl, 'https://img.example/poster.jpg');
    expect(items.single.description, 'Описание аниме');
    expect(items.single.rating, 8.2);
    expect(items.single.categories, contains('2025'));
    expect(items.single.videoUrl, isEmpty);
  });

  test('does not make requests for blank queries or unsupported categories', () async {
    var calls = 0;
    final source = AniLibriaCatalogSource(
      client: MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );

    expect(
      await source.search(' ', kind: MediaSourceKind.anime),
      isEmpty,
    );
    expect(
      await source.search('film', kind: MediaSourceKind.movie),
      isEmpty,
    );
    expect(calls, 0);
  });

  test('reports non-200 responses so the aggregator can isolate the source', () async {
    final source = AniLibriaCatalogSource(
      client: MockClient((request) async => http.Response('blocked', 403)),
    );

    expect(
      () => source.search('test', kind: MediaSourceKind.anime),
      throwsA(isA<HttpException>()),
    );
  });
}
