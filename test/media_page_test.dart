import 'dart:async';
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
import 'package:omni_ai/features/media/services/media_resume_position_store.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

void main() {
  test('media headers use generic browser headers without a provider origin', () {
    final headers = MediaHeaders.getHeaders(
      'https://video.example/path/stream.m3u8',
    );

    expect(headers['User-Agent'], contains('Chrome/122.0.0.0'));
    expect(headers['Referer'], isNull);
    expect(headers['Origin'], isNull);
    expect(headers['Accept'], '*/*');
    expect(MediaHeaders.getHeaders('')['Referer'], isNull);
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
    final controllers = <_FakePlaybackController>[];
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
            final controller = _FakePlaybackController(
              initializationError: source.host == 'primary.example'
                  ? PlatformException(code: 'video_unavailable')
                  : null,
            );
            controllers.add(controller);
            return controller;
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
    expect(controllers, hasLength(2));
    expect(controllers.first.isDisposed, isTrue);
    expect(controllers.last.isDisposed, isFalse);
  });

  testWidgets('retries a fallback video URL after a network error', (
    tester,
  ) async {
    final playerSources = <Uri>[];
    final controllers = <_FakePlaybackController>[];
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
            final controller = _FakePlaybackController(
              initializationError: source.host == 'primary.example'
                  ? const SocketException('Connection failed')
                  : null,
            );
            controllers.add(controller);
            return controller;
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
    expect(controllers, hasLength(2));
    expect(controllers.first.isDisposed, isTrue);
    expect(controllers.last.isDisposed, isFalse);
  });

  testWidgets('disposes every controller when all stream sources fail', (
    tester,
  ) async {
    final playerSources = <Uri>[];
    final controllers = <_FakePlaybackController>[];
    final item = MediaItem(
      id: 'all-sources-fail-test',
      title: 'All Sources Fail Test',
      type: 'Фильм',
      posterUrl: '',
      rating: 8,
      voiceovers: const [],
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
            final controller = _FakePlaybackController(
              initializationError: StateError('Initialization failed'),
            );
            controllers.add(controller);
            return controller;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(playerSources, [
      Uri.parse('https://primary.example/video.mp4'),
      Uri.parse('https://mirror.example/video.mp4'),
    ]);
    expect(controllers, hasLength(2));
    expect(controllers.every((controller) => controller.isDisposed), isTrue);
    expect(find.text('ВИДЕО НЕДОСТУПНО НА ЭТОЙ ПЛАТФОРМЕ'), findsOneWidget);
    expect(find.text('StateError'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers to resume playback from the saved position', (
    tester,
  ) async {
    final resumeStore = _FakeMediaResumePositionStore()
      ..positions['resume-test:0'] = const Duration(minutes: 12, seconds: 34);
    final controller = _FakePlaybackController(
      duration: const Duration(minutes: 90),
    );
    final item = MediaItem(
      id: 'resume-test',
      title: 'Resume Test',
      type: 'Фильм',
      posterUrl: '',
      rating: 8,
      voiceovers: const [],
      videoUrl: 'https://example.com/resume.mp4',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          resumePositionStore: resumeStore,
          playerFactory: (_) => controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Продолжить просмотр?'), findsOneWidget);
    expect(find.text('Вы остановились на 12:34.'), findsOneWidget);
    await tester.tap(find.text('ПРОДОЛЖИТЬ'));
    await tester.pumpAndSettle();

    expect(controller.position, const Duration(minutes: 12, seconds: 34));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an honest empty state instead of demo media', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: MediaPage(preferences: UserPreferences())),
    );

    expect(find.text('МЕДИАКАТАЛОГ НЕ ПОДКЛЮЧЁН'), findsOneWidget);
    expect(find.text('OMNI AI  //  MEDIA'), findsOneWidget);
    expect(find.text('KAIROS  //  MEDIA DECK'), findsNothing);
    expect(find.text('Cyberpunk: Edgerunners'), findsNothing);
    expect(find.text('Интерстеллар'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('media-search')),
      'Cyberpunk',
    );
    await tester.pumpAndSettle();

    expect(find.text('Cyberpunk: Edgerunners'), findsNothing);
    expect(find.text('Интерстеллар'), findsNothing);
    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets('shows persistent watched history for series and anime', (
    tester,
  ) async {
    final store = _FakeMediaResumePositionStore()
      ..watchedEpisodes['history-test'] = <int>{0};
    final item = MediaItem(
      id: 'history-test',
      title: 'History Test',
      type: 'Аниме',
      posterUrl: '',
      rating: 8,
      voiceovers: const [],
      videoUrl: 'https://example.com/episode-1.mp4',
      episodes: const [
        MediaEpisode(number: 1, title: 'First', videoUrl: 'https://example.com/episode-1.mp4'),
        MediaEpisode(number: 2, title: 'Second', videoUrl: 'https://example.com/episode-2.mp4'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          resumePositionStore: store,
          playerFactory: (_) => _FakePlaybackController(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ПРОСМОТРЕНО: 1 ИЗ 2 СЕРИЙ'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('episode-selector')),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('episode-selector')));
    await tester.pumpAndSettle();
    expect(find.textContaining('✓  СЕРИЯ 01'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('player changes episode source and selects preferred voiceover', (
    tester,
  ) async {
    final playerSources = <Uri>[];
    final controllers = <_FakePlaybackController>[];
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
          voiceoverVideoUrls: {
            'Studio A': 'https://example.com/studio-a-first.mp4',
            'Original': 'https://example.com/original-first.mp4',
          },
        ),
        MediaEpisode(
          number: 2,
          title: 'Second',
          videoUrl: 'https://example.com/second.mp4',
          voiceoverVideoUrls: {
            'Studio A': 'https://example.com/studio-a-second.mp4',
            'Original': 'https://example.com/original-second.mp4',
          },
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
            final controller = _FakePlaybackController();
            controllers.add(controller);
            return controller;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(playerSources, [
      Uri.parse('https://example.com/original-first.mp4'),
    ]);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('voiceover-selector')),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    final voiceoverField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('voiceover-selector')),
    );
    expect(voiceoverField.initialValue, 'Original');
    await tester.tap(find.byKey(const ValueKey('voiceover-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Studio A').last);
    await tester.pumpAndSettle();
    expect(playerSources.last, Uri.parse('https://example.com/studio-a-first.mp4'));
    expect(controllers[0].isDisposed, isTrue);
    expect(controllers[1].isDisposed, isFalse);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('episode-selector')),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('episode-selector')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('Second').last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      playerSources.last,
      Uri.parse('https://example.com/studio-a-second.mp4'),
    );
    expect(controllers[1].isDisposed, isTrue);
    expect(controllers[2].isDisposed, isFalse);
  });

  testWidgets('disposes a stale player when episode changes during initialization', (
    tester,
  ) async {
    final firstInitialization = Completer<void>();
    final playerSources = <Uri>[];
    final controllers = <_FakePlaybackController>[];
    final item = MediaItem(
      id: 'stale-player-test',
      title: 'Stale Player Test',
      type: 'Сериал',
      posterUrl: '',
      rating: 8,
      voiceovers: const [],
      videoUrl: 'https://example.com/first.mp4',
      episodes: const [
        MediaEpisode(
          number: 1,
          title: 'First',
          videoUrl: 'https://example.com/first.mp4',
        ),
        MediaEpisode(
          number: 2,
          title: 'Second',
          videoUrl: 'https://example.com/second.mp4',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          playerFactory: (source) {
            playerSources.add(source);
            final controller = _FakePlaybackController(
              initializationCompleter: source.path.endsWith('first.mp4')
                  ? firstInitialization
                  : null,
            );
            controllers.add(controller);
            return controller;
          },
        ),
      ),
    );
    await tester.pump();
    expect(controllers, hasLength(1));

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('episode-selector')),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('episode-selector')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('Second').last);
    await tester.pump(const Duration(milliseconds: 300));

    expect(playerSources.last, Uri.parse('https://example.com/second.mp4'));
    expect(controllers, hasLength(2));
    expect(controllers[1].isDisposed, isFalse);

    firstInitialization.complete();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controllers.first.isDisposed, isTrue);
    expect(controllers[1].isDisposed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('voiceover selector excludes voices without a stream', (
    tester,
  ) async {
    final item = MediaItem(
      id: 'voiceover-availability-test',
      title: 'Voiceover Availability Test',
      type: 'Фильм',
      posterUrl: '',
      rating: 8,
      voiceovers: const ['Studio A', 'Original'],
      videoUrl: 'https://example.com/default.mp4',
      voiceoverVideoUrls: const {
        'Original': 'https://example.com/original.mp4',
      },
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('voiceover-selector')),
      160,
      scrollable: find.byType(Scrollable).last,
    );

    final selector = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('voiceover-selector')),
    );
    expect(selector.initialValue, 'Original');
    await tester.tap(find.byKey(const ValueKey('voiceover-selector')));
    await tester.pumpAndSettle();
    expect(find.text('Studio A'), findsNothing);
  });

  testWidgets('skip intro and credits controls seek to expected positions', (
    tester,
  ) async {
    const duration = Duration(minutes: 90);
    final controller = _FakePlaybackController(duration: duration)
      ..position = const Duration(seconds: 10);
    final item = MediaItem(
      id: 'skip-controls-test',
      title: 'Skip Controls Test',
      type: 'Сериал',
      posterUrl: '',
      rating: 8,
      voiceovers: const [],
      videoUrl: 'https://example.com/video.mp4',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          resumePositionStore: _FakeMediaResumePositionStore(),
          playerFactory: (_) => controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('skip-intro-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('skip-credits-button')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('skip-intro-button')));
    await tester.pumpAndSettle();
    expect(controller.position, const Duration(seconds: 100));

    controller.position = duration - const Duration(minutes: 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('skip-credits-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('skip-credits-button')));
    await tester.pumpAndSettle();
    expect(controller.position, duration - const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('playback control awaits play and pause state changes', (
    tester,
  ) async {
    final controller = _FakePlaybackController();
    final item = MediaItem(
      id: 'play-pause-test',
      title: 'Play Pause Test',
      type: 'Фильм',
      posterUrl: '',
      rating: 8,
      voiceovers: const ['Original'],
      videoUrl: 'https://example.com/video.mp4',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          playerFactory: (_) => controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Воспроизвести'), findsOneWidget);
    await tester.tap(find.byTooltip('Воспроизвести'));
    await tester.pumpAndSettle();
    expect(controller.isPlaying, isTrue);
    expect(find.byTooltip('Пауза'), findsOneWidget);

    await tester.tap(find.byTooltip('Пауза'));
    await tester.pumpAndSettle();
    expect(controller.isPlaying, isFalse);
    expect(find.byTooltip('Воспроизвести'), findsOneWidget);
  });

  testWidgets('shows playback errors without hiding the video', (
    tester,
  ) async {
    final controller = _FakePlaybackController(
      playError: StateError('Playback failed'),
    );
    final item = MediaItem(
      id: 'play-error-test',
      title: 'Playback Error Test',
      type: 'Фильм',
      posterUrl: '',
      rating: 8,
      voiceovers: const ['Original'],
      videoUrl: 'https://example.com/video.mp4',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          playerFactory: (_) => controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Воспроизвести'));
    await tester.pumpAndSettle();

    expect(find.text('ОШИБКА ВОСПРОИЗВЕДЕНИЯ: StateError'), findsOneWidget);
    expect(find.byTooltip('Воспроизвести'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
  _FakePlaybackController({
    this.initializationError,
    this.initializationCompleter,
    this.playError,
    this.duration = const Duration(minutes: 90),
  });

  final Object? initializationError;
  final Completer<void>? initializationCompleter;
  final Object? playError;
  bool _isPlaying = false;
  bool isDisposed = false;

  @override
  Duration position = Duration.zero;

  @override
  final Duration duration;

  @override
  bool get isInitialized => true;

  @override
  bool get isPlaying => _isPlaying;

  @override
  double get aspectRatio => 16 / 9;

  @override
  Future<void> initialize() async {
    if (initializationError case final error?) throw error;
    await initializationCompleter?.future;
  }

  @override
  Future<void> play() async {
    if (playError case final error?) throw error;
    _isPlaying = true;
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
  }

  @override
  Future<void> seekTo(Duration position) async {
    this.position = position;
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }

  @override
  Widget buildView() => const ColoredBox(color: Colors.black);
}

class _FakeMediaResumePositionStore implements MediaResumePositionStore {
  final Map<String, Duration> positions = <String, Duration>{};
  final Map<String, Set<int>> watchedEpisodes = <String, Set<int>>{};

  String _key(String mediaId, int episodeIndex) => '$mediaId:$episodeIndex';

  @override
  Future<Duration?> load(String mediaId, int episodeIndex) async =>
      positions[_key(mediaId, episodeIndex)];

  @override
  Future<void> save(
    String mediaId,
    int episodeIndex,
    Duration position,
    Duration duration,
  ) async {
    positions[_key(mediaId, episodeIndex)] = position;
  }

  @override
  Future<Set<int>> loadWatchedEpisodes(String mediaId) async =>
      Set<int>.from(watchedEpisodes[mediaId] ?? <int>{});

  @override
  Future<void> markEpisodeWatched(String mediaId, int episodeIndex) async {
    watchedEpisodes.putIfAbsent(mediaId, () => <int>{}).add(episodeIndex);
  }

  @override
  Future<void> clear(String mediaId, int episodeIndex) async {
    positions.remove(_key(mediaId, episodeIndex));
  }
}
