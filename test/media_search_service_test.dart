import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/domain/media_hub_contracts.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

void main() {
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
