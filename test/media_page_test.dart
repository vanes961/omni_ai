import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/network/widgets/network_image_with_fallback.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/presentation/media_page.dart';
import 'package:omni_ai/features/media/presentation/player_page.dart';
import 'package:omni_ai/features/media/services/media_headers.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

void main() {
  test('media headers emulate desktop Chrome with Kinopoisk origin', () {
    final headers = MediaHeaders.getHeaders(
      'https://video.example/path/stream.m3u8',
    );

    expect(headers['User-Agent'], contains('Chrome/122.0.0.0'));
    expect(headers['Referer'], 'https://kinopoisk.ru/');
    expect(headers['Origin'], 'https://kinopoisk.ru');
    expect(headers['Accept'], '*/*');
    expect(MediaHeaders.getHeaders('')['Origin'], isNull);
  });

  testWidgets('network images use a User-Agent and try fallback URLs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkImageWithFallback(
            url: 'https://primary.example/poster.jpg',
            fallbackUrls: const ['https://backup.example/poster.jpg'],
            headers: MediaHeaders.getHeaders(
              'https://primary.example/poster.jpg',
            ),
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox(key: ValueKey('poster-error')),
          ),
        ),
      ),
    );
    final primary = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(primary.imageUrl, 'https://primary.example/poster.jpg');
    expect(
      primary.httpHeaders?['User-Agent'],
      MediaHeaders.getHeaders(
        'https://primary.example/poster.jpg',
      )['User-Agent'],
    );
    final fallback =
        primary.errorWidget!(
              tester.element(find.byType(CachedNetworkImage)),
              primary.imageUrl,
              Exception('primary image failed'),
            )
            as CachedNetworkImage;
    expect(fallback.imageUrl, 'https://backup.example/poster.jpg');
    expect(fallback.httpHeaders, primary.httpHeaders);
  });

  testWidgets('retries a fallback video URL after PlatformException', (
    tester,
  ) async {
    final playerSources = <Uri>[];
    final item = MediaItem(
      id: 'fallback-test',
      title: 'Fallback Test',
      type: 'Фильм',
      posterUrl: '',
      rating: 8.0,
      voiceovers: const ['Original'],
      videoUrl: 'https://primary.example/video.mp4',
      videoFallbackUrls: const ['https://mirror.example/video.mp4'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          playerFactory: (source) {
            playerSources.add(source);
            return _FakePlaybackController(
              initializationError: source.host == 'primary.example'
                  ? PlatformException(code: 'video_unavailable')
                  : null,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(playerSources, [
      Uri.parse('https://primary.example/video.mp4'),
      Uri.parse('https://mirror.example/video.mp4'),
    ]);
    expect(find.text('ВИДЕО НЕДОСТУПНО НА ЭТОЙ ПЛАТФОРМЕ'), findsNothing);
  });

  testWidgets('retries a fallback video URL after a network error', (
    tester,
  ) async {
    final playerSources = <Uri>[];
    final item = MediaItem(
      id: 'network-fallback-test',
      title: 'Network Fallback Test',
      type: 'Фильм',
      posterUrl: '',
      rating: 8.0,
      voiceovers: const ['Original'],
      videoUrl: 'https://primary.example/video.mp4',
      videoFallbackUrls: const ['https://mirror.example/video.mp4'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          playerFactory: (source) {
            playerSources.add(source);
            return _FakePlaybackController(
              initializationError: source.host == 'primary.example'
                  ? const SocketException('Connection failed')
                  : null,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(playerSources, [
      Uri.parse('https://primary.example/video.mp4'),
      Uri.parse('https://mirror.example/video.mp4'),
    ]);
    expect(find.text('ВИДЕО НЕДОСТУПНО НА ЭТОЙ ПЛАТФОРМЕ'), findsNothing);
  });

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

  testWidgets('long episode titles do not overflow the player layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final item = MediaItem(
      id: 'long-title-test',
      title: 'Long title test',
      type: 'Сериал',
      posterUrl: '',
      rating: 8,
      voiceovers: const ['Original voiceover with a very long name'],
      videoUrl: 'https://example.com/video.mp4',
      episodes: const [
        MediaEpisode(
          number: 1,
          title:
              'A very long episode title that used to overflow the screen width',
          videoUrl: 'https://example.com/video.mp4',
        ),
        MediaEpisode(
          number: 2,
          title: 'Second episode',
          videoUrl: 'https://example.com/video.mp4',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          playerFactory: (_) => _FakePlaybackController(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

class _FakePlaybackController implements MediaPlaybackController {
  _FakePlaybackController({this.initializationError});

  final Object? initializationError;
  bool _isPlaying = false;

  @override
  bool get isInitialized => true;

  @override
  bool get isPlaying => _isPlaying;

  @override
  double get aspectRatio => 16 / 9;

  @override
  Future<void> initialize() async {
    if (initializationError case final error?) throw error;
  }

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
