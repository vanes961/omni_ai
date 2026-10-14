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
