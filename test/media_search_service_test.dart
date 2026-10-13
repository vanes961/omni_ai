import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
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

  test('opens the public Zona catalog without requiring a Kinopoisk key', () {
    expect(MediaSearchService.zonaCatalogUri.scheme, 'https');
    expect(MediaSearchService.zonaCatalogUri.host, 'w1.zona.im');
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
}
