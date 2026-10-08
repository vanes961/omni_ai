import 'package:flutter_test/flutter_test.dart';
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
}
