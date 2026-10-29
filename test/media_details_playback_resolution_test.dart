import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/data/video_source_engine.dart';
import 'package:omni_ai/features/media/presentation/media_details_page.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

void main() {
  const item = MediaItem(
    id: 'catalog:movie:123',
    title: 'Тестовый фильм',
    type: 'Фильм',
    posterUrl: '',
    rating: 7.5,
    voiceovers: [],
    videoUrl: '',
    description: 'Описание',
  );

  testWidgets(
    'shows automatic playback when a source engine is configured',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaDetailsPage(
            item: item,
            searchService: MediaSearchService(),
            preferences: UserPreferences(),
            videoSourceEngine: VideoSourceEngine(const []),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('СМОТРЕТЬ'), findsOneWidget);
      expect(find.text('ВИДЕОИСТОЧНИК НЕ ПОДКЛЮЧЁН'), findsNothing);
    },
  );

  testWidgets(
    'does not offer automatic playback when no source engine or URL exists',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaDetailsPage(
            item: item,
            searchService: MediaSearchService(),
            preferences: UserPreferences(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('СМОТРЕТЬ'), findsNothing);
      expect(find.text('ВИДЕОИСТОЧНИК НЕ ПОДКЛЮЧЁН'), findsOneWidget);
    },
  );
}
