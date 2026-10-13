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
