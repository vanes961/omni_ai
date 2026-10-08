import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/network/network_service.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

void main() {
  const service = MediaSearchService();

  test(
    'search filters immediately by title, type, category, and voiceover',
    () {
      expect(
        service.search('cyberpunk').single.title,
        'Cyberpunk: Edgerunners',
      );
      expect(service.search('', type: 'Фильм'), hasLength(2));
      expect(service.search('fantasy'), isEmpty);
      expect(service.search('Anilibria'), hasLength(2));
    },
  );

  test(
    'recommendations follow selected onboarding categories and favorites',
    () {
      final preferences = UserPreferences()
        ..categories = ['Аниме']
        ..favoriteTitles = ['Атака Титанов'];

      final recommendations = service.recommendedFor(preferences);

      expect(recommendations, hasLength(2));
      expect(recommendations.first.title, 'Атака Титанов');
      expect(recommendations.every((item) => item.type == 'Аниме'), isTrue);
    },
  );

  test(
    'preferred voiceover picks the first available onboarding preference',
    () {
      final preferences = UserPreferences()
        ..voiceDubbing = ['RHS', 'Anilibria'];
      final anime = service.catalog.first;
      final series = service.catalog.singleWhere((item) => item.id == 'arcane');

      expect(service.preferredVoiceover(anime, preferences), 'Anilibria');
      expect(service.preferredVoiceover(series, preferences), 'RHS');
    },
  );

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
