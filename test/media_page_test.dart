import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/media/services/ani_skip_segment_provider.dart';
import 'package:omni_ai/core/network/widgets/network_image_with_fallback.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/data/torrserver_client.dart';
import 'package:omni_ai/features/media/data/torrserver_playback_resolver.dart';
import 'package:omni_ai/features/media/presentation/media_details_page.dart';
import 'package:omni_ai/features/media/presentation/media_page.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/media/services/media_catalog_token_store.dart';
import 'package:omni_ai/features/media/presentation/player_page.dart';
import 'package:omni_ai/features/media/services/media_headers.dart';
import 'package:omni_ai/features/media/services/media_playback_settings_store.dart';
import 'package:omni_ai/features/media/services/media_resume_position_store.dart';
import 'package:omni_ai/features/media/services/media_segment_marker_store.dart';
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

  testWidgets('cancelling torrent file selection does not start fallback playback', (
    tester,
  ) async {
    final playerSources = <Uri>[];
    final item = MediaItem(
      id: 'torrent-cancel-test',
      title: 'Torrent Cancel Test',
      type: 'Фильм',
      posterUrl: '',
      rating: 8,
      voiceovers: const [],
      videoUrl: 'magnet:?xt=urn:btih:0123456789abcdef',
      videoFallbackUrls: const ['https://fallback.example/video.mp4'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences()
            ..torrServerUrl = 'http://torrserver.example',
          torrServerResolver: _FileSelectionRequiredResolver(),
          playerFactory: (source) {
            playerSources.add(source);
            return _FakePlaybackController();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ВЫБЕРИТЕ ВИДЕОФАЙЛ'), findsOneWidget);
    await tester.tap(find.text('ОТМЕНА'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(playerSources, isEmpty);
    expect(find.text('НЕ УДАЛОСЬ ЗАПУСТИТЬ ВИДЕО'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    expect(find.text('НЕ УДАЛОСЬ ЗАПУСТИТЬ ВИДЕО'), findsNothing);
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
    expect(find.text('НЕ УДАЛОСЬ ЗАПУСТИТЬ ВИДЕО'), findsNothing);
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
    expect(find.text('НЕ УДАЛОСЬ ЗАПУСТИТЬ ВИДЕО'), findsOneWidget);
    expect(find.textContaining('Тип ошибки: StateError'), findsOneWidget);
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

  testWidgets('marks an episode watched when stale resume progress is near its end', (
    tester,
  ) async {
    final resumeStore = _FakeMediaResumePositionStore()
      ..positions['near-end-resume-test:0'] = const Duration(
        minutes: 89,
        seconds: 50,
      );
    final item = MediaItem(
      id: 'near-end-resume-test',
      title: 'Near End Resume Test',
      type: 'Сериал',
      posterUrl: '',
      rating: 8,
      voiceovers: const [],
      videoUrl: 'https://example.com/episode-1.mp4',
      episodes: const [
        MediaEpisode(
          number: 1,
          title: 'First',
          videoUrl: 'https://example.com/episode-1.mp4',
        ),
        MediaEpisode(
          number: 2,
          title: 'Second',
          videoUrl: 'https://example.com/episode-2.mp4',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          resumePositionStore: resumeStore,
          playerFactory: (_) => _FakePlaybackController(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Продолжить просмотр?'), findsNothing);
    expect(resumeStore.positions.containsKey('near-end-resume-test:0'), isFalse);
    expect(resumeStore.watchedEpisodes['near-end-resume-test'], contains(0));
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

    expect(
      find.textContaining('отсутствует TMDB_ACCESS_TOKEN'),
      findsOneWidget,
    );
    expect(find.text('Cyberpunk: Edgerunners'), findsNothing);
    expect(find.text('Интерстеллар'), findsNothing);
    expect(find.byType(PlayerPage), findsNothing);
  });

  testWidgets('secure catalog token overrides build-time token for online search', (
    tester,
  ) async {
    String? authorization;
    final client = MockClient((request) async {
      authorization = request.headers['Authorization'];
      return http.Response(
        '{"results":[{"id":123,"media_type":"movie","title":"Secure Token Film","original_language":"en","poster_path":null,"vote_average":7.8,"genre_ids":[],"overview":"Real catalog result"}]}',
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final tokenStore = _FakeCatalogTokenStore()..token = 'secure-device-token';

    await tester.pumpWidget(
      MaterialApp(
        home: MediaPage(
          preferences: UserPreferences(),
          searchService: MediaSearchService(
            accessToken: 'build-time-token',
            client: client,
          ),
          catalogTokenStore: tokenStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('media-search')),
      'Secure Token Film',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(authorization, 'Bearer secure-device-token');
    expect(find.text('Secure Token Film'), findsNWidgets(2));
    expect(find.textContaining('отсутствует TMDB_ACCESS_TOKEN'), findsNothing);
    expect(tester.takeException(), isNull);
    client.close();
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('watched-episode-count')),
      160,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('player-page-scroll')),
        matching: find.byType(Scrollable),
      ),
    );

    expect(find.byKey(const ValueKey('watched-episode-count')), findsOneWidget);
    expect(find.text('ПРОСМОТРЕНО: 1 ИЗ 2 СЕРИЙ'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('episode-selector')),
      160,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('player-page-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('episode-selector')));
    await tester.pumpAndSettle();
    expect(find.textContaining('✓  СЕРИЯ 01'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('episode playback does not fall back to another item URL', (
    tester,
  ) async {
    const episodeUrl = 'https://example.com/season-1-episode-1.mp4';
    const unrelatedFallback = 'https://example.com/unrelated-series-fallback.mp4';
    final sources = <Uri>[];
    final item = MediaItem(
      id: 'episode-fallback-isolation-test',
      title: 'Episode fallback isolation',
      type: 'Сериал',
      posterUrl: '',
      rating: 8,
      voiceovers: const ['Studio A'],
      videoUrl: 'https://example.com/series-default.mp4',
      videoFallbackUrls: const [unrelatedFallback],
      voiceoverVideoUrls: const {
        'Studio A': 'https://example.com/unrelated-voiceover.mp4',
      },
      videoSources: const [
        MediaVideoSource(
          url: 'https://example.com/unrelated-quality-variant.mp4',
          quality: '1080p',
        ),
      ],
      episodes: const [
        MediaEpisode(
          number: 1,
          title: 'Episode one',
          videoUrl: episodeUrl,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          playerFactory: (source) {
            sources.add(source);
            if (source.toString() == episodeUrl) {
              return _FakePlaybackController(
                initializationError: StateError('Episode stream unavailable'),
              );
            }
            return _FakePlaybackController();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(sources, [Uri.parse(episodeUrl)]);
    expect(sources, isNot(contains(Uri.parse(unrelatedFallback))));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AniSkip uses absolute episode numbering across seasons', (
    tester,
  ) async {
    final requestedPaths = <String>[];
    final aniSkip = AniSkipSegmentProvider(
      client: MockClient((request) async {
        requestedPaths.add(request.url.path);
        return http.Response('{"found":false,"results":[]}', 200);
      }),
    );
    final item = MediaItem(
      id: 'aniskip-season-numbering-test',
      title: 'AniSkip Season Numbering Test',
      type: 'Аниме',
      posterUrl: '',
      rating: 8,
      voiceovers: const [],
      videoUrl: 'https://example.com/season-1-episode-1.mp4',
      malId: 9253,
      episodes: const [
        MediaEpisode(
          number: 1,
          seasonNumber: 1,
          title: 'Season one episode one',
          videoUrl: 'https://example.com/season-1-episode-1.mp4',
        ),
        MediaEpisode(
          number: 2,
          seasonNumber: 1,
          title: 'Season one episode two',
          videoUrl: 'https://example.com/season-1-episode-2.mp4',
        ),
        MediaEpisode(
          number: 1,
          seasonNumber: 2,
          title: 'Season two episode one',
          videoUrl: 'https://example.com/season-2-episode-1.mp4',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          aniSkipSegmentProvider: aniSkip,
          playerFactory: (_) => _FakePlaybackController(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('/v2/skip-times/9253/1'));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('season-selector')),
      160,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('player-page-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('season-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('СЕЗОН 02').last);
    await tester.pumpAndSettle();

    expect(requestedPaths, contains('/v2/skip-times/9253/3'));
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
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('player-page-scroll')),
        matching: find.byType(Scrollable),
      ),
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
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('player-page-scroll')),
        matching: find.byType(Scrollable),
      ),
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

  testWidgets('saves playback progress when the app is backgrounded', (
    tester,
  ) async {
    final resumeStore = _FakeMediaResumePositionStore();
    late _FakePlaybackController controller;
    final item = MediaItem(
      id: 'background-progress-test',
      title: 'Background Progress Test',
      type: 'Фильм',
      posterUrl: '',
      rating: 8,
      voiceovers: const [],
      videoUrl: 'https://example.com/background-progress.mp4',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          resumePositionStore: resumeStore,
          playerFactory: (_) {
            controller = _FakePlaybackController();
            return controller;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.position = const Duration(minutes: 8, seconds: 17);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(
      resumeStore.positions['background-progress-test:0'],
      const Duration(minutes: 8, seconds: 17),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('saves the previous episode position before switching', (
    tester,
  ) async {
    final resumeStore = _FakeMediaResumePositionStore();
    final controllers = <_FakePlaybackController>[];
    final item = MediaItem(
      id: 'switch-progress-test',
      title: 'Switch Progress Test',
      type: 'Сериал',
      posterUrl: '',
      rating: 8,
      voiceovers: const [],
      videoUrl: 'https://example.com/episode-1.mp4',
      episodes: const [
        MediaEpisode(
          number: 1,
          title: 'First',
          videoUrl: 'https://example.com/episode-1.mp4',
        ),
        MediaEpisode(
          number: 2,
          title: 'Second',
          videoUrl: 'https://example.com/episode-2.mp4',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          resumePositionStore: resumeStore,
          playerFactory: (_) {
            final controller = _FakePlaybackController();
            controllers.add(controller);
            return controller;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    controllers.first.position = const Duration(minutes: 12, seconds: 34);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('episode-selector')),
      160,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('player-page-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('episode-selector')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.textContaining('Second').last);
    await tester.pumpAndSettle();

    expect(
      resumeStore.positions['switch-progress-test:0'],
      const Duration(minutes: 12, seconds: 34),
    );
    expect(controllers.first.isDisposed, isTrue);
    expect(controllers.last.isDisposed, isFalse);
    expect(tester.takeException(), isNull);
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
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('player-page-scroll')),
        matching: find.byType(Scrollable),
      ),
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
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('player-page-scroll')),
        matching: find.byType(Scrollable),
      ),
    );

    final selector = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('voiceover-selector')),
    );
    expect(selector.initialValue, 'Original');
    await tester.tap(find.byKey(const ValueKey('voiceover-selector')));
    await tester.pumpAndSettle();
    expect(find.text('Studio A'), findsNothing);
  });

  testWidgets('playback timeline and ten-second seek controls work', (
    tester,
  ) async {
    const duration = Duration(minutes: 90);
    final controller = _FakePlaybackController(duration: duration)
      ..position = const Duration(seconds: 20);
    final item = MediaItem(
      id: 'timeline-controls-test',
      title: 'Timeline Controls Test',
      type: 'Фильм',
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

    expect(
      find.byKey(const ValueKey('playback-progress-slider')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('seek-back-10')), findsOneWidget);
    expect(find.byKey(const ValueKey('seek-forward-10')), findsOneWidget);
    expect(find.text('0:20'), findsOneWidget);
    expect(find.text('1:30:00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('seek-back-10')));
    await tester.pumpAndSettle();
    expect(controller.position, const Duration(seconds: 10));

    await tester.tap(find.byKey(const ValueKey('seek-forward-10')));
    await tester.pumpAndSettle();
    expect(controller.position, const Duration(seconds: 20));

    controller.position = Duration.zero;
    await tester.tap(find.byKey(const ValueKey('seek-back-10')));
    await tester.pumpAndSettle();
    expect(controller.position, Duration.zero);

    controller.position = duration - const Duration(seconds: 5);
    await tester.tap(find.byKey(const ValueKey('seek-forward-10')));
    await tester.pumpAndSettle();
    expect(controller.position, duration);

    expect(find.byKey(const ValueKey('fullscreen-toggle')), findsOneWidget);
    expect(find.byTooltip('Полноэкранный режим'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

    final markerStore = _FakeMediaSegmentMarkerStore()
      ..markers['skip-controls-test:0'] = [
        MediaSegmentMarker(
          type: MediaSegmentType.intro,
          start: const Duration(seconds: 5),
          end: const Duration(seconds: 20),
        ),
        MediaSegmentMarker(
          type: MediaSegmentType.credits,
          start: duration - const Duration(minutes: 2),
          end: duration - const Duration(seconds: 5),
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          resumePositionStore: _FakeMediaResumePositionStore(),
          segmentMarkerStore: markerStore,
          playerFactory: (_) => controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('skip-intro-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('skip-credits-button')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('skip-intro-button')));
    await tester.pumpAndSettle();
    expect(controller.position, const Duration(seconds: 20));

    controller.position = duration - const Duration(minutes: 1);
    await tester.pump(const Duration(seconds: 1));
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

    expect(find.textContaining('Тип ошибки: StateError'), findsOneWidget);
    expect(find.byTooltip('Воспроизвести'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quality selector is available without voiceovers', (
    tester,
  ) async {
    final sources = <Uri>[];
    final settings = _FakeMediaPlaybackSettingsStore();
    final item = MediaItem(
      id: 'quality-without-voiceover-test',
      title: 'Quality Without Voiceover',
      type: 'Фильм',
      posterUrl: '',
      rating: 8,
      voiceovers: const [],
      videoUrl: 'https://example.com/default.mp4',
      videoSources: const [
        MediaVideoSource(
          url: 'https://example.com/720.mp4',
          quality: '720p',
        ),
        MediaVideoSource(
          url: 'https://example.com/1080.mp4',
          quality: '1080p',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          playbackSettingsStore: settings,
          playerFactory: (source) {
            sources.add(source);
            return _FakePlaybackController();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('quality-selector')),
      find.descendant(
        of: find.byKey(const ValueKey('player-page-scroll')),
        matching: find.byType(Scrollable),
      ),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quality-selector')), findsOneWidget);
    expect(sources.first, Uri.parse('https://example.com/720.mp4'));
    await tester.tap(find.byKey(const ValueKey('quality-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1080p').last);
    await tester.pumpAndSettle();

    expect(sources.last, Uri.parse('https://example.com/1080.mp4'));
    expect(settings.savedQuality, '1080p');
    expect(tester.takeException(), isNull);
  });

  testWidgets('player selects real quality variants and likes voiceovers', (
    tester,
  ) async {
    final sources = <Uri>[];
    final settings = _FakeMediaPlaybackSettingsStore();
    final item = MediaItem(
      id: 'quality-voiceover-test',
      title: 'Quality Test',
      type: 'Фильм',
      posterUrl: '',
      rating: 8,
      voiceovers: const ['Studio A'],
      videoUrl: 'https://example.com/default.mp4',
      videoSources: const [
        MediaVideoSource(
          url: 'https://example.com/720.mp4',
          quality: '720p',
          voiceover: 'Studio A',
        ),
        MediaVideoSource(
          url: 'https://example.com/1080.mp4',
          quality: '1080p',
          voiceover: 'Studio A',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences()..voiceDubbing = ['Studio A'],
          playbackSettingsStore: settings,
          playerFactory: (source) {
            sources.add(source);
            return _FakePlaybackController();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(sources.first, Uri.parse('https://example.com/720.mp4'));
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('quality-selector')),
      find.descendant(
        of: find.byKey(const ValueKey('player-page-scroll')),
        matching: find.byType(Scrollable),
      ),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quality-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1080p').last);
    await tester.pumpAndSettle();
    expect(sources.last, Uri.parse('https://example.com/1080.mp4'));
    expect(settings.savedQuality, '1080p');

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('voiceover-like-button')),
      find.descendant(
        of: find.byKey(const ValueKey('player-page-scroll')),
        matching: find.byType(Scrollable),
      ),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('voiceover-like-button')));
    await tester.pumpAndSettle();
    expect(settings.likedVoiceovers, contains('Studio A'));
    expect(find.text('Озвучка нравится'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('player selects seasons and filters the episode list', (
    tester,
  ) async {
    final sources = <Uri>[];
    final item = MediaItem(
      id: 'season-selector-test',
      title: 'Season Test',
      type: 'Сериал',
      posterUrl: '',
      rating: 8,
      voiceovers: const [],
      videoUrl: 'https://example.com/season-1-episode-1.mp4',
      episodes: const [
        MediaEpisode(
          number: 1,
          title: 'First season episode one',
          videoUrl: 'https://example.com/season-1-episode-1.mp4',
          seasonNumber: 1,
        ),
        MediaEpisode(
          number: 2,
          title: 'First season episode two',
          videoUrl: 'https://example.com/season-1-episode-2.mp4',
          seasonNumber: 1,
        ),
        MediaEpisode(
          number: 1,
          title: 'Second season episode one',
          videoUrl: 'https://example.com/season-2-episode-1.mp4',
          seasonNumber: 2,
        ),
        MediaEpisode(
          number: 2,
          title: 'Second season episode two',
          videoUrl: 'https://example.com/season-2-episode-2.mp4',
          seasonNumber: 2,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          item: item,
          preferences: UserPreferences(),
          playerFactory: (source) {
            sources.add(source);
            return _FakePlaybackController();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('season-selector')),
      find.descendant(
        of: find.byKey(const ValueKey('player-page-scroll')),
        matching: find.byType(Scrollable),
      ),
      const Offset(0, -160),
    );
    expect(find.byKey(const ValueKey('season-selector')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('season-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('СЕЗОН 02').last);
    await tester.pumpAndSettle();

    expect(
      sources.last,
      Uri.parse('https://example.com/season-2-episode-1.mp4'),
    );
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('episode-selector')),
      find.descendant(
        of: find.byKey(const ValueKey('player-page-scroll')),
        matching: find.byType(Scrollable),
      ),
      const Offset(0, -160),
    );
    await tester.tap(find.byKey(const ValueKey('episode-selector')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('СЕРИЯ 01  //  Second season episode one'),
      findsWidgets,
    );
    expect(find.textContaining('First season episode one'), findsNothing);
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

  testWidgets('user-selected source overrides catalog variants and fallbacks', (
    tester,
  ) async {
    final playerSources = <Uri>[];
    const item = MediaItem(
      id: 'manual-source-priority-test',
      title: 'Manual Source Priority',
      type: 'Фильм',
      posterUrl: '',
      rating: 8,
      voiceovers: ['Existing dub'],
      videoUrl: 'https://catalog.example/original.mp4',
      videoFallbackUrls: ['https://catalog.example/fallback.mp4'],
      voiceoverVideoUrls: {
        'Existing dub': 'https://catalog.example/dub.mp4',
      },
      videoSources: [
        MediaVideoSource(
          url: 'https://catalog.example/4k.mp4',
          quality: '4K',
          voiceover: 'Existing dub',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaDetailsPage(
          item: item,
          searchService: const MediaSearchService(),
          preferences: UserPreferences(),
          playerFactory: (source) {
            playerSources.add(source);
            return _FakePlaybackController();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('choose-media-source')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://selected.example/film.mp4',
    );
    await tester.tap(find.text('ОТКРЫТЬ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(playerSources, isNotEmpty);
    expect(
      playerSources.first,
      Uri.parse('https://selected.example/film.mp4'),
    );
    expect(
      playerSources,
      isNot(contains(Uri.parse('https://catalog.example/4k.mp4'))),
    );
    expect(
      playerSources,
      isNot(contains(Uri.parse('https://catalog.example/dub.mp4'))),
    );
    expect(
      playerSources,
      isNot(contains(Uri.parse('https://catalog.example/fallback.mp4'))),
    );
    expect(tester.takeException(), isNull);
  });


  testWidgets('filters media search results by genre and rating', (
    tester,
  ) async {
    final service = _FakeMediaSearchService([
      MediaItem(
        id: 'comedy',
        title: 'Comedy Movie',
        type: 'Фильм',
        posterUrl: '',
        rating: 6.5,
        voiceovers: const [],
        videoUrl: '',
        categories: const ['Комедия'],
      ),
      MediaItem(
        id: 'thriller',
        title: 'Thriller Movie',
        type: 'Фильм',
        posterUrl: '',
        rating: 9.0,
        voiceovers: const [],
        videoUrl: '',
        categories: const ['Триллер'],
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaPage(
          preferences: UserPreferences(),
          searchService: service,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('media-search')),
      'Movie',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();

    expect(find.text('Comedy Movie'), findsOneWidget);
    expect(find.text('Thriller Movie'), findsOneWidget);
    expect(find.byKey(const ValueKey('media-genre-Комедия')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('media-genre-Комедия')),
    );
    await tester.tap(find.byKey(const ValueKey('media-genre-Комедия')));
    await tester.pumpAndSettle();
    expect(find.text('Comedy Movie'), findsOneWidget);
    expect(find.text('Thriller Movie'), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('media-genre-all')));
    await tester.tap(find.byKey(const ValueKey('media-genre-all')));
    await tester.pumpAndSettle();
    final ratingFilter = find.byKey(const ValueKey('media-sort-rating'));
    await tester.ensureVisible(ratingFilter);
    await tester.tap(ratingFilter);
    await tester.pumpAndSettle();
    expect(ratingFilter, findsOneWidget);
    expect(find.text('Сначала высокий рейтинг'), findsOneWidget);
    expect(find.text('Comedy Movie'), findsOneWidget);
    expect(find.text('Thriller Movie'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Thriller Movie')).dy,
      lessThan(tester.getTopLeft(find.text('Comedy Movie')).dy),
    );
  });

}


class _FakeMediaSearchService extends MediaSearchService {
  _FakeMediaSearchService(this.items);

  final List<MediaItem> items;

  @override
  List<MediaItem> search(String query, {String? type}) => const [];

  @override
  Future<List<MediaItem>> searchOnline(String query, {String? type}) async =>
      items
          .where((item) => item.title.toLowerCase().contains(query.toLowerCase()))
          .where((item) => type == null || item.type == type)
          .toList();
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

class _FakeMediaSegmentMarkerStore implements MediaSegmentMarkerStore {
  final Map<String, List<MediaSegmentMarker>> markers = {};

  String _key(String mediaId, int episodeIndex) => '$mediaId:$episodeIndex';

  @override
  Future<List<MediaSegmentMarker>> load(String mediaId, int episodeIndex) async =>
      List<MediaSegmentMarker>.from(markers[_key(mediaId, episodeIndex)] ?? []);

  @override
  Future<void> save(
    String mediaId,
    int episodeIndex,
    List<MediaSegmentMarker> markers,
  ) async {
    this.markers[_key(mediaId, episodeIndex)] =
        List<MediaSegmentMarker>.from(markers);
  }
}


class _FakeMediaPlaybackSettingsStore implements MediaPlaybackSettingsStore {
  String? savedVoiceover;
  String? savedQuality;
  final Set<String> likedVoiceovers = <String>{};

  @override
  Future<String?> loadVoiceover(String mediaId) async => savedVoiceover;

  @override
  Future<void> saveVoiceover(String mediaId, String voiceover) async {
    savedVoiceover = voiceover;
  }

  @override
  Future<String?> loadQuality(String mediaId) async => savedQuality;

  @override
  Future<void> saveQuality(String mediaId, String quality) async {
    savedQuality = quality;
  }

  @override
  Future<Set<String>> loadLikedVoiceovers() async =>
      Set<String>.from(likedVoiceovers);

  @override
  Future<bool> toggleVoiceoverLike(String voiceover) async {
    if (likedVoiceovers.remove(voiceover)) return false;
    likedVoiceovers.add(voiceover);
    return true;
  }
}
class _FileSelectionRequiredResolver extends TorrServerPlaybackResolver {
  @override
  Future<Uri> resolve({
    required String endpoint,
    required Uri magnetUri,
    String? title,
    int? episodeNumber,
    int? seasonNumber,
    int? selectedFileIndex,
    String? existingTorrentHash,
    Duration metadataTimeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(seconds: 1),
  }) async {
    throw const TorrServerFileSelectionRequired(
      [
        TorrServerFileStat(
          id: 1,
          path: 'Season 1/Episode 1.mkv',
          length: 1024,
        ),
        TorrServerFileStat(
          id: 2,
          path: 'Season 1/Episode 2.mkv',
          length: 2048,
        ),
      ],
      torrentHash: 'test-hash',
    );
  }
}


class _FakeCatalogTokenStore implements MediaCatalogTokenStore {
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async {
    token = value.trim();
  }

  @override
  Future<void> deleteToken() async {
    token = null;
  }
}
