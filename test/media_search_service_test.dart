import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/sources/media_source.dart';
import 'package:omni_ai/features/media/sources/media_source_engine.dart';
import 'package:omni_ai/features/media/domain/media_hub_contracts.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

void main() {
  test('searches AniLibria for anime when TMDB is not configured', () async {
    final source = _FakeAnimeSource();
    final service = MediaSearchService(
      sourceEngine: MediaSourceEngine([source]),
    );

    final items = await service.searchOnline('наруто', type: 'Аниме');

    expect(source.lastQuery, 'наруто');
    expect(items.map((item) => item.title), ['Наруто']);
  });

  test('falls back to AniLibria when TMDB has no anime results', () async {
    final source = _FakeAnimeSource();
    final service = MediaSearchService(
      accessToken: 'test-token',
      sourceEngine: MediaSourceEngine([source]),
      client: MockClient((request) async {
        expect(request.url.path, '/3/search/tv');
        return http.Response('{"results":[]}', 200);
      }),
    );

    final items = await service.searchOnline('наруто', type: 'Аниме');

    expect(items.single.id, 'anilibria:42');
    expect(source.lastQuery, 'наруто');
  });

  test('prefers PoiskKino results before making a TMDB request', () async {
    var tmdbRequested = false;
    final source = _FakeFilmSeriesSource();
    final service = MediaSearchService(
      accessToken: 'tmdb-token',
      kinopoiskApiKey: 'poiskkino-token',
      sourceEngine: MediaSourceEngine([source]),
      client: MockClient((request) async {
        tmdbRequested = true;
        return http.Response('{"results":[]}', 200);
      }),
    );

    final items = await service.searchOnline('Интерстеллар', type: 'Фильм');

    expect(items.single.id, 'kinopoisk:77');
    expect(items.single.title, 'Интерстеллар');
    expect(tmdbRequested, isFalse);
  });

  test('supports runtime PoiskKino key injection without losing TMDB token', () {
    final service = MediaSearchService(
      accessToken: 'tmdb-token',
    ).withKinopoiskApiKey('  poiskkino-token  ');

    expect(service.accessToken, 'tmdb-token');
    expect(service.kinopoiskApiKey, 'poiskkino-token');
    expect(
      service.withAccessToken('updated-tmdb-token').kinopoiskApiKey,
      'poiskkino-token',
    );
  });

  const service = MediaSearchService();

  test('does not expose fabricated demo titles in the local catalog', () {
    expect(service.catalog, isEmpty);
    expect(service.trending, isEmpty);
    expect(service.search('cyberpunk'), isEmpty);
    expect(service.search('', type: 'Фильм'), isEmpty);
    expect(service.search('Anilibria'), isEmpty);
  });

  test('recommendations stay empty until real catalog metadata is available', () {
    final preferences = UserPreferences()
      ..categories = ['Аниме']
      ..favoriteTitles = ['Атака Титанов'];

    expect(service.recommendedFor(preferences), isEmpty);
  });

  test('loads real trending titles from the TMDB response', () async {
    final service = MediaSearchService(
      accessToken: 'test-token',
      client: MockClient((request) async {
        expect(request.url.path, '/3/trending/all/week');
        expect(request.url.queryParameters['language'], 'ru-RU');
        expect(request.headers['Authorization'], 'Bearer test-token');
        return http.Response(
          '{"results":['
          '{"id":11,"media_type":"movie","title":"Real Film",'
          '"overview":"Summary","poster_path":"/film.jpg",'
          '"vote_average":8.2,"genre_ids":[28]},'
          '{"id":12,"media_type":"tv","name":"Real Series",'
          '"original_language":"en","origin_country":["US"],'
          '"vote_average":7.5,"genre_ids":[18]}'
          ']}',
          200,
        );
      }),
    );

    final items = await service.fetchTrendingOnline();

    expect(items, hasLength(2));
    expect(items.first.id, 'tmdb:movie:11');
    expect(items.first.title, 'Real Film');
    expect(items.first.posterUrl, 'https://image.tmdb.org/t/p/w500/film.jpg');
    expect(items.first.categories, contains('Боевик'));
    expect(items.last.type, 'Сериал');
    expect(items.last.title, 'Real Series');
  });

  test('uses PoiskKino for trending films without a TMDB token', () async {
    Uri? requestedUri;
    final service = MediaSearchService(
      kinopoiskApiKey: 'poiskkino-token',
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          '{"docs":[{"id":77,"name":"Каталоговый фильм","type":"movie",'
          '"rating":{"kp":8.2},"poster":{"url":"https://img.example/poster.jpg"}}]}',
          200,
        );
      }),
    );

    final items = await service.fetchTrendingOnline(type: 'Фильм');

    expect(requestedUri?.host, 'api.poiskkino.dev');
    expect(requestedUri?.path, '/v1.5/movie');
    expect(requestedUri?.queryParameters['type'], 'movie');
    expect(items.single.id, 'kinopoisk:77');
    expect(items.single.title, 'Каталоговый фильм');
  });

  test('fetches recommendations using saved favorite genres', () async {
    final requestedPaths = <String>[];
    final service = MediaSearchService(
      accessToken: 'test-token',
      client: MockClient((request) async {
        requestedPaths.add(request.url.path);
        expect(request.url.queryParameters['with_genres'], '28');
        if (request.url.path.endsWith('/movie')) {
          return http.Response(
            '{"results":[{"id":21,"title":"Action Film",'
            '"media_type":"movie","genre_ids":[28],"vote_average":8.1}]}',
            200,
          );
        }
        return http.Response(
          '{"results":[{"id":22,"name":"Action Series",'
          '"original_language":"en","origin_country":["US"],'
          '"genre_ids":[28],"vote_average":7.9}]}',
          200,
        );
      }),
    );

    final items = await service.fetchRecommendationsOnline(
      interests: const ['Боевик'],
    );

    expect(requestedPaths, containsAll(['/3/discover/movie', '/3/discover/tv']));
    expect(items.map((item) => item.title), containsAll(['Action Film', 'Action Series']));
  });

  test('does not query TMDB for interests without known genre metadata', () async {
    var requested = false;
    final service = MediaSearchService(
      accessToken: 'test-token',
      client: MockClient((request) async {
        requested = true;
        return http.Response('{"results":[]}', 200);
      }),
    );

    expect(
      await service.fetchRecommendationsOnline(
        interests: const ['unknown custom interest'],
      ),
      isEmpty,
    );
    expect(requested, isFalse);
  });

  test('filters online trending to the requested media type', () async {
    final service = MediaSearchService(
      accessToken: 'test-token',
      client: MockClient((request) async => http.Response(
        '{"results":['
        '{"id":11,"media_type":"movie","title":"Film"},'
        '{"id":12,"media_type":"tv","name":"Series",'
        '"original_language":"en","origin_country":["US"]}'
        ']}',
        200,
      )),
    );

    final items = await service.fetchTrendingOnline(type: 'Фильм');

    expect(items, hasLength(1));
    expect(items.single.title, 'Film');
  });

  test('returns no trending data when the TMDB request fails', () async {
    final service = MediaSearchService(
      accessToken: 'test-token',
      client: MockClient((request) async => http.Response('unavailable', 503)),
    );

    expect(await service.fetchTrendingOnline(), isEmpty);
  });

  test('parses TMDB season summaries in season-number order', () {
    final seasons = MediaSearchService.parseCatalogSeasons([
      {'season_number': 2, 'name': 'Season 2', 'episode_count': 8},
      {'season_number': 0, 'name': 'Specials', 'episode_count': 1},
      {'season_number': -1, 'name': 'Invalid'},
      {'season_number': 3, 'name': ''},
    ]);

    expect(seasons, hasLength(2));
    expect(seasons.first.seasonNumber, 0);
    expect(seasons.last.name, 'Season 2');
    expect(seasons.last.episodeCount, 8);
  });

  test('parses TMDB collection parts and excludes the current movie', () {
    final films = MediaSearchService.parseCollectionParts(
      [
        {'id': 20, 'title': 'Second film', 'release_date': '2020-01-01'},
        {'id': 10, 'title': 'First film', 'release_date': '2010-01-01'},
        {'id': 30, 'title': 'Current film', 'release_date': '2015-01-01'},
        {'id': 40, 'title': '   '},
        'invalid entry',
      ],
      currentMovieId: 30,
    );

    expect(films, hasLength(2));
    expect(films.map((film) => film.title), ['First film', 'Second film']);
    expect(films.first.id, 'tmdb:movie:10');
  });

  test('franchise chronology resolver can enrich catalog entries', () async {
    var requestedId = '';
    final entries = [
      const MediaFranchiseEntry(
        id: 'tmdb:movie:10',
        title: 'Film A',
        overview: '',
        releaseDate: '2020-01-01',
        posterUrl: '',
      ),
    ];
    final service = MediaSearchService(
      franchiseChronologyResolver: ({required franchiseId, required entries}) async {
        requestedId = franchiseId;
        return [
          MediaFranchiseEntry(
            id: entries.single.id,
            title: entries.single.title,
            overview: entries.single.overview,
            releaseDate: entries.single.releaseDate,
            posterUrl: entries.single.posterUrl,
            chronologyOrder: 1,
            chronologySourceUrl: 'https://example.org/film-a',
          ),
        ];
      },
    );

    final result = await service.resolveFranchiseChronology(
      franchiseId: 'tmdb:collection:99',
      entries: entries,
    );

    expect(requestedId, 'tmdb:collection:99');
    expect(result.single.chronologyOrder, 1);
  });

  test('franchise chronology resolver cannot change franchise membership',
      () async {
    const original = MediaFranchiseEntry(
      id: 'tmdb:movie:10',
      title: 'Film A',
      overview: '',
      releaseDate: '2020-01-01',
      posterUrl: '',
    );
    final service = MediaSearchService(
      franchiseChronologyResolver: ({required franchiseId, required entries}) async => [
        const MediaFranchiseEntry(
          id: 'tmdb:movie:999',
          title: 'Unrelated film',
          overview: '',
          releaseDate: '2000-01-01',
          posterUrl: '',
          chronologyOrder: 1,
        ),
      ],
    );

    final result = await service.resolveFranchiseChronology(
      franchiseId: 'tmdb:collection:99',
      entries: const [original],
    );

    expect(result.single.id, original.id);
    expect(result.single.chronologyOrder, isNull);
  });

  test('franchise chronology resolver failure falls back safely', () async {
    const original = MediaFranchiseEntry(
      id: 'tmdb:movie:10',
      title: 'Film A',
      overview: '',
      releaseDate: '2020-01-01',
      posterUrl: '',
    );
    final service = MediaSearchService(
      franchiseChronologyResolver: ({required franchiseId, required entries}) async {
        throw Exception('Cloud unavailable');
      },
    );

    final result = await service.resolveFranchiseChronology(
      franchiseId: 'tmdb:collection:99',
      entries: const [original],
    );

    expect(result.single.id, original.id);
    expect(result.single.chronologyOrder, isNull);
  });

  test('smart franchise order falls back when chronology is unverified', () {
    final entries = [
      const MediaFranchiseEntry(
        id: 'later',
        title: 'Later release',
        overview: '',
        releaseDate: '2020-01-01',
        posterUrl: '',
      ),
      const MediaFranchiseEntry(
        id: 'earlier',
        title: 'Earlier release',
        overview: '',
        releaseDate: '2010-01-01',
        posterUrl: '',
      ),
    ];

    expect(
      MediaSearchService.orderFranchiseItems(
        entries,
        FranchiseViewingOrder.smart,
      ).map((entry) => entry.id),
      ['earlier', 'later'],
    );
  });

  test('chronology order is used only with verified positions', () {
    final entries = [
      const MediaFranchiseEntry(
        id: 'release-first',
        title: 'Release first',
        overview: '',
        releaseDate: '2010-01-01',
        posterUrl: '',
        chronologyOrder: 2,
      ),
      const MediaFranchiseEntry(
        id: 'story-first',
        title: 'Story first',
        overview: '',
        releaseDate: '2020-01-01',
        posterUrl: '',
        chronologyOrder: 1,
      ),
    ];

    expect(
      MediaSearchService.orderFranchiseItems(
        entries,
        FranchiseViewingOrder.chronology,
      ).map((entry) => entry.id),
      ['story-first', 'release-first'],
    );
    expect(
      MediaSearchService.orderFranchiseItems(
        entries
            .map(
              (entry) => MediaFranchiseEntry(
                id: entry.id,
                title: entry.title,
                overview: entry.overview,
                releaseDate: entry.releaseDate,
                posterUrl: entry.posterUrl,
                chronologyOrder: entry.chronologyOrder,
                chronologySpoilerRisk: entry.id == 'story-first',
              ),
            )
            .toList(),
        FranchiseViewingOrder.smart,
      ).map((entry) => entry.id),
      ['release-first', 'story-first'],
    );
  });

  test('invalid chronology positions fall back to release order', () {
    final entries = [
      const MediaFranchiseEntry(
        id: 'first-release',
        title: 'First release',
        overview: '',
        releaseDate: '2010-01-01',
        posterUrl: '',
        chronologyOrder: 1,
      ),
      const MediaFranchiseEntry(
        id: 'second-release',
        title: 'Second release',
        overview: '',
        releaseDate: '2020-01-01',
        posterUrl: '',
        chronologyOrder: 1,
      ),
    ];

    expect(
      MediaSearchService.orderFranchiseItems(
        entries,
        FranchiseViewingOrder.chronology,
      ).map((entry) => entry.id),
      ['first-release', 'second-release'],
    );
  });

  test('parses TMDB season metadata without creating playable stream URLs', () {
    final episodes = MediaSearchService.parseSeasonEpisodes(
      {
        'episodes': [
          {
            'episode_number': 2,
            'name': 'Second episode',
            'overview': 'Episode summary',
            'air_date': '2025-02-01',
            'still_path': '/episode.jpg',
          },
          {'episode_number': 1, 'name': 'First episode'},
          {'episode_number': 3, 'name': ''},
          'invalid entry',
        ],
      },
      seasonNumber: 4,
    );

    expect(episodes, hasLength(2));
    expect(episodes.first.seasonNumber, 4);
    expect(episodes.first.episodeNumber, 1);
    expect(episodes.first.title, 'First episode');
    expect(episodes.last.stillUrl, 'https://image.tmdb.org/t/p/w500/episode.jpg');
    expect(episodes.last.airDate, '2025-02-01');
  });

  test('does not invent voiceovers for an unavailable catalog item', () {
    final preferences = UserPreferences()
      ..voiceDubbing = ['RHS', 'Anilibria'];
    const item = MediaItem(
      id: 'external-item',
      title: 'External result',
      type: 'Фильм',
      posterUrl: '',
      rating: 0,
      voiceovers: [],
      videoUrl: '',
    );

    expect(service.preferredVoiceover(item, preferences), isNull);
  });

  group('MediaStreamSource validation', () {
    test('accepts HTTP(S) URLs with a host and no embedded credentials', () {
      final http = MediaStreamSource(
        id: 'http',
        label: 'HTTP source',
        uri: Uri.parse('http://media.example/film.mp4'),
      );
      final https = MediaStreamSource(
        id: 'https',
        label: 'HTTPS source',
        uri: Uri.parse('https://media.example/film.mp4'),
      );

      expect(http.isSupportedInput, isTrue);
      expect(https.isSupportedInput, isTrue);
    });

    test('accepts magnet links with a valid hexadecimal BitTorrent hash', () {
      final source = MediaStreamSource(
        id: 'magnet',
        label: 'Magnet source',
        uri: Uri.parse(
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
        ),
      );

      expect(source.isMagnet, isTrue);
      expect(source.isSupportedInput, isTrue);
    });

    test('rejects unsupported, malformed, and credential-bearing URLs', () {
      final file = MediaStreamSource(
        id: 'file',
        label: 'Local file',
        uri: Uri.parse('file:///film.mp4'),
      );
      final missingHost = MediaStreamSource(
        id: 'missing-host',
        label: 'Invalid HTTPS',
        uri: Uri.parse('https:/film.mp4'),
      );
      final malformedMagnet = MediaStreamSource(
        id: 'bad-magnet',
        label: 'Invalid magnet',
        uri: Uri.parse('magnet:?xt=urn:btih:not-a-valid-hash'),
      );
      final credentials = MediaStreamSource(
        id: 'credentials',
        label: 'Credential URL',
        uri: Uri.parse('https://user:password@media.example/film.mp4'),
      );

      expect(file.isSupportedInput, isFalse);
      expect(missingHost.isSupportedInput, isFalse);
      expect(malformedMagnet.isSupportedInput, isFalse);
      expect(credentials.isSupportedInput, isFalse);
    });
  });
}

class _FakeAnimeSource implements MediaSource {
  String? lastQuery;

  @override
  String get id => 'fake-anime';

  @override
  Set<MediaSourceKind> get supportedKinds => const {MediaSourceKind.anime};

  @override
  Future<List<MediaItem>> search(
    String query, {
    required MediaSourceKind kind,
  }) async {
    lastQuery = query;
    return [
      MediaItem(
        id: 'anilibria:42',
        title: 'Наруто',
        type: 'Аниме',
        posterUrl: '',
        rating: 8,
        voiceovers: const [],
        videoUrl: '',
      ),
    ];
  }
}

class _FakeFilmSeriesSource implements MediaSource {
  @override
  String get id => 'fake-poiskkino';

  @override
  Set<MediaSourceKind> get supportedKinds => const {
    MediaSourceKind.movie,
    MediaSourceKind.series,
  };

  @override
  Future<List<MediaItem>> search(
    String query, {
    required MediaSourceKind kind,
  }) async {
    return [
      MediaItem(
        id: 'kinopoisk:77',
        title: 'Интерстеллар',
        type: kind == MediaSourceKind.series ? 'Сериал' : 'Фильм',
        posterUrl: '',
        rating: 8.7,
        voiceovers: const [],
        videoUrl: '',
        description: 'Карточка из основного каталога.',
      ),
    ];
  }
}
