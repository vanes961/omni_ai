import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/network/network_service.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
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

  test('recommendations stay empty until a real catalog is connected', () {
    final preferences = UserPreferences()
      ..categories = ['Аниме']
      ..favoriteTitles = ['Атака Титанов'];

    expect(service.recommendedFor(preferences), isEmpty);
  });

  test('does not invent voiceovers for an unavailable catalog item', () {
    final preferences = UserPreferences()
      ..voiceDubbing = ['RHS', 'Anilibria'];
    const item = MediaItem(
      id: 'online-item',
      title: 'Online result',
      type: 'Фильм',
      posterUrl: '',
      rating: 0,
      voiceovers: [],
      videoUrl: '',
    );

    expect(service.preferredVoiceover(item, preferences), isNull);
  });

  test('online search maps Kinopoisk metadata and sends the API key', () async {
    http.Request? request;
    final service = MediaSearchService(
      apiKey: 'test-key',
      networkService: NetworkService(
        client: MockClient((capturedRequest) async {
          request = capturedRequest;
          return http.Response(
            '{"searchFilms":[{"filmId":42,"nameRu":"Тестовый фильм",'
            '"type":"FILM","rating":"8,4","description":"Описание",'
            '"posterUrl":"https://example.com/poster.jpg",'
            '"genres":[{"genre":"драма"}]}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    final result = await service.searchOnline(' тест ');

    expect(request?.headers['x-api-key'], 'test-key');
    expect(request?.url.queryParameters['keyword'], 'тест');
    expect(result.single.id, 'kinopoisk-42');
    expect(result.single.title, 'Тестовый фильм');
    expect(result.single.rating, 8.4);
    expect(result.single.description, 'Описание');
    expect(result.single.categories, ['драма']);
    expect(result.single.videoUrl, isEmpty);
  });
}
