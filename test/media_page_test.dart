import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/presentation/media_page.dart';
import 'package:omni_ai/features/media/presentation/player_page.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

void main() {
  testWidgets(
    'filters the catalog and opens the selected title in the player',
    (tester) async {
      final playerSources = <Uri>[];
      final preferences = UserPreferences()..voiceDubbing = ['Anilibria'];
      await tester.pumpWidget(
        MaterialApp(
          home: MediaPage(
            preferences: preferences,
            playerFactory: (source) {
              playerSources.add(source);
              return _FakePlaybackController();
            },
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('media-search')),
        'Cyberpunk',
      );
      await tester.pumpAndSettle();
      expect(find.text('Cyberpunk: Edgerunners'), findsOneWidget);
      expect(find.text('Интерстеллар'), findsNothing);

      await tester.tap(find.text('Cyberpunk: Edgerunners'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('episode-selector')),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Anilibria'), findsOneWidget);
      expect(playerSources, [
        Uri.parse(MediaSearchService().catalog.first.videoUrl),
      ]);
    },
  );

  testWidgets('player changes episode source and selects preferred voiceover', (
    tester,
  ) async {
    final playerSources = <Uri>[];
    final item = MediaItem(
      id: 'series-test',
      title: 'Test Series',
      type: 'Сериал',
      posterUrl: '',
      rating: 8.0,
      voiceovers: const ['Studio A', 'Original'],
      videoUrl: 'https://example.com/first.mp4',
      episodes: const [
        MediaEpisode(
          number: 1,
          title: 'Pilot',
          videoUrl: 'https://example.com/first.mp4',
        ),
        MediaEpisode(
          number: 2,
          title: 'Second',
          videoUrl: 'https://example.com/second.mp4',
        ),
      ],
    );
    final preferences = UserPreferences()..voiceDubbing = ['Original'];

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: preferences,
          playerFactory: (source) {
            playerSources.add(source);
            return _FakePlaybackController();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(playerSources, [Uri.parse('https://example.com/first.mp4')]);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('voiceover-selector')),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    final voiceoverField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('voiceover-selector')),
    );
    expect(voiceoverField.initialValue, 'Original');

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('episode-selector')),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('episode-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Second').last);
    await tester.pumpAndSettle();
    expect(playerSources.last, Uri.parse('https://example.com/second.mp4'));
  });
}

class _FakePlaybackController implements MediaPlaybackController {
  bool _isPlaying = false;

  @override
  bool get isInitialized => true;

  @override
  bool get isPlaying => _isPlaying;

  @override
  double get aspectRatio => 16 / 9;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> play() async {
    _isPlaying = true;
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
  }

  @override
  Future<void> dispose() async {}

  @override
  Widget buildView() => const ColoredBox(color: Colors.black);
}
