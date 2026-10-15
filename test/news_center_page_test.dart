import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:omni_ai/features/news/data/shared_preferences_news_cache.dart';
import 'package:omni_ai/features/news/data/news_interest_repository.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';
import 'package:omni_ai/features/news/models/news_article.dart';
import 'package:omni_ai/features/news/presentation/news_center_page.dart';
import 'package:omni_ai/features/news/services/news_rss_service.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

void main() {
  testWidgets('renders real RSS candidates on first visit with saved interests', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repository = _MemoryNewsInterestRepository(
      const NewsInterestProfile(topics: ['anime']),
    );
    var requestCount = 0;
    final service = NewsRssService(
      client: MockClient((_) async {
        requestCount++;
        return http.Response(
          '<rss><channel><item>'
          '<title>Anime: New season announced</title>'
          '<link>https://publisher.example/anime-season</link>'
          '<description>A publisher announced the next anime season.</description>'
          '<pubDate>Mon, 12 Oct 2026 09:00:00 GMT</pubDate>'
          '<source>Anime News</source>'
          '</item><item>'
          '<title>Anime: Second story in the feed</title>'
          '<link>https://publisher.example/anime-second</link>'
          '<description>Another relevant anime announcement.</description>'
          '<pubDate>Mon, 12 Oct 2026 08:00:00 GMT</pubDate>'
          '<source>Anime News</source>'
          '</item></channel></rss>',
          200,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NewsCenterPage(repository: repository, newsService: service),
      ),
    );
    // The news screen contains indeterminate progress indicators, so
    // pump a bounded interval instead of waiting for every animation.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(requestCount, greaterThan(0));
    expect(find.byType(NewsCenterPage), findsOneWidget);
    expect(find.text('Anime: New season announced'), findsOneWidget);
    expect(find.textContaining('ANIME NEWS'), findsWidgets);
    for (
      var i = 0;
      i < 12 &&
          find.text('Anime: Second story in the feed').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Anime: Second story in the feed'), findsOneWidget);
    for (
      var i = 0;
      i < 12 && find.text('Диагностика системы').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Диагностика системы'), findsOneWidget);
    expect(find.text('Не удалось загрузить новости.'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Диагностика системы'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Диагностика OMNI AI'), findsOneWidget);
    expect(find.textContaining('Этап:'), findsOneWidget);
    expect(find.textContaining('Время RSS:'), findsOneWidget);
    expect(find.textContaining('Время локализации:'), findsOneWidget);
    expect(find.textContaining('Рекомендуемый следующий шаг:'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });


  testWidgets('refreshes interests saved while news cache is loading', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repository = _MemoryNewsInterestRepository(
      const NewsInterestProfile(),
    );
    final cacheStore = _DelayedNewsCacheStore();
    var requestCount = 0;
    final service = NewsRssService(
      client: MockClient((_) async {
        requestCount++;
        return http.Response(
          '<rss><channel><item>'
          '<title>Anime: Saved during cache restoration</title>'
          '<link>https://publisher.example/cache-race</link>'
          '<description>A story fetched after saving interests.</description>'
          '<pubDate>Mon, 12 Oct 2026 09:00:00 GMT</pubDate>'
          '<source>Anime News</source>'
          '</item></channel></rss>',
          200,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NewsCenterPage(
          repository: repository,
          newsService: service,
          newsCache: SharedPreferencesNewsCache(store: cacheStore),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(requestCount, 0);

    for (
      var i = 0;
      i < 12 && find.text('ВАШИ ИНТЕРЕСЫ').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('ВАШИ ИНТЕРЕСЫ'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'anime');
    await tester.tap(find.byTooltip('Добавить тему'));
    await tester.pump();
    await tester.ensureVisible(find.text('СОХРАНИТЬ ИНТЕРЕСЫ'));
    await tester.tap(find.text('СОХРАНИТЬ ИНТЕРЕСЫ'));
    await tester.pump();

    // Let cache restoration finish only after the new profile is saved.
    cacheStore.releaseReads.complete();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(requestCount, 3);
    // The interests controls are below the feed; return to the top so the
    // lazy list builds the article card before asserting its visibility.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 1600));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Anime: Saved during cache restoration'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps fetched articles visible when cache persistence fails', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repository = _MemoryNewsInterestRepository(
      const NewsInterestProfile(topics: ['anime']),
    );
    final service = NewsRssService(
      client: MockClient((_) async => http.Response(
        '<rss><channel><item>'
        '<title>Anime: Cache failure regression</title>'
        '<link>https://publisher.example/cache-failure</link>'
        '<description>A feed item remains usable without offline persistence.</description>'
        '<pubDate>Mon, 12 Oct 2026 09:00:00 GMT</pubDate>'
        '<source>Anime News</source>'
        '</item></channel></rss>',
        200,
        headers: {'content-type': 'application/rss+xml; charset=utf-8'},
      )),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NewsCenterPage(
          repository: repository,
          newsService: service,
          newsCache: SharedPreferencesNewsCache(
            store: _FailingNewsCacheStore(),
          ),
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Anime: Cache failure regression'), findsOneWidget);
    expect(
      find.text(
        'Новости загружены, но не удалось сохранить их для офлайн-доступа.',
      ),
      findsOneWidget,
    );
    for (
      var i = 0;
      i < 12 && find.text('Диагностика системы').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Диагностика системы'), findsOneWidget);
    await tester.tap(find.text('Диагностика системы'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.textContaining('Предупреждение кэша:'), findsOneWidget);
    expect(
      find.textContaining(
        'Ошибка: Новости загружены, но не удалось сохранить их для офлайн-доступа.',
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('restores the saved personalized articles without refetching', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    await preferences.setString(
      'omni_ai.news_cache.articles.v1',
      '[{"id":"cached-anime-1","title":"Saved anime announcement",'
      '"summary":"A previously loaded article.","sourceName":"Anime News",'
      '"sourceUrl":"https://publisher.example/cached-anime",'
      '"publishedAt":"2026-10-12T09:00:00.000Z","topics":["anime"],'
      '"language":"ru","region":"ru","isCritical":false,'
      '"isVerified":true,"contentType":"article"}]',
    );
    await preferences.setString('omni_ai.news_cache.topics.v1', '["anime"]');
    await preferences.setString(
      'omni_ai.news_cache.critical_setting.v1',
      'false',
    );
    await preferences.setString(
      'omni_ai.news_cache.saved_at.v1',
      DateTime.now().toUtc().toIso8601String(),
    );
    final repository = _MemoryNewsInterestRepository(
      const NewsInterestProfile(topics: ['anime']),
    );
    var requestCount = 0;
    final service = NewsRssService(
      client: MockClient((_) async {
        requestCount++;
        return http.Response('<rss><channel /></rss>', 200);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NewsCenterPage(repository: repository, newsService: service),
      ),
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Saved anime announcement'), findsOneWidget);
    expect(requestCount, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('refreshes a stale cached feed automatically', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    await preferences.setString(
      'omni_ai.news_cache.articles.v1',
      '[{"id":"cached-anime-1","title":"Saved anime announcement",'
      '"summary":"A previously loaded article.","sourceName":"Anime News",'
      '"sourceUrl":"https://publisher.example/cached-anime",'
      '"publishedAt":"2026-10-12T09:00:00.000Z","topics":["anime"],'
      '"language":"ru","region":"ru","isCritical":false,'
      '"isVerified":true,"contentType":"article"}]',
    );
    await preferences.setString('omni_ai.news_cache.topics.v1', '["anime"]');
    await preferences.setString(
      'omni_ai.news_cache.critical_setting.v1',
      'false',
    );
    await preferences.setString(
      'omni_ai.news_cache.saved_at.v1',
      '2026-10-12T09:00:00.000Z',
    );
    final repository = _MemoryNewsInterestRepository(
      const NewsInterestProfile(topics: ['anime']),
    );
    var requestCount = 0;
    final service = NewsRssService(
      client: MockClient((_) async {
        requestCount++;
        return http.Response('''<rss><channel><item>
          <title>Fresh anime announcement</title>
          <link>https://publisher.example/fresh-anime</link>
          <description>Anime news update.</description>
          <pubDate>Wed, 14 Oct 2026 09:00:00 GMT</pubDate>
          <source>Anime News</source>
        </item></channel></rss>''', 200);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NewsCenterPage(repository: repository, newsService: service),
      ),
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Saved anime announcement'), findsOneWidget);
    expect(requestCount, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalidates a cached feed when saved interests differ', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    await preferences.setString(
      'omni_ai.news_cache.articles.v1',
      '[{"id":"old-anime","title":"Old anime cache story",'
      '"summary":"Belongs to an old topic.","sourceName":"Anime News",'
      '"sourceUrl":"https://publisher.example/old-anime",'
      '"publishedAt":"2026-10-12T09:00:00.000Z","topics":["anime"],'
      '"language":"ru","region":"ru","isCritical":false,'
      '"isVerified":true,"contentType":"article"}]',
    );
    await preferences.setString('omni_ai.news_cache.topics.v1', '["anime"]');
    await preferences.setString(
      'omni_ai.news_cache.critical_setting.v1',
      'false',
    );
    final repository = _MemoryNewsInterestRepository(
      const NewsInterestProfile(topics: ['manga']),
    );
    var requestCount = 0;
    final service = NewsRssService(
      client: MockClient((_) async {
        requestCount++;
        return http.Response(
          '<rss><channel><item>'
          '<title>Manga: New volume announced</title>'
          '<link>https://publisher.example/manga-volume</link>'
          '<description>A new manga volume was announced.</description>'
          '<pubDate>Mon, 12 Oct 2026 09:00:00 GMT</pubDate>'
          '<source>Manga News</source>'
          '</item></channel></rss>',
          200,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NewsCenterPage(repository: repository, newsService: service),
      ),
    );
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(requestCount, greaterThan(0));
    expect(find.text('Old anime cache story'), findsNothing);
    expect(find.text('Manga: New volume announced'), findsOneWidget);
    expect(
      await preferences.getString('omni_ai.news_cache.topics.v1'),
      '["manga"]',
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('discards an RSS response after interests change mid-request', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    final repository = _MemoryNewsInterestRepository(
      const NewsInterestProfile(topics: ['anime']),
    );
    final response = Completer<http.Response>();
    var requestCount = 0;
    final service = NewsRssService(
      client: MockClient((_) {
        requestCount++;
        return response.future;
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NewsCenterPage(repository: repository, newsService: service),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(requestCount, greaterThan(0));
    await tester.ensureVisible(find.text('ВАШИ ИНТЕРЕСЫ'));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(find.byType(InputChip), findsOneWidget);

    await tester.ensureVisible(find.byType(InputChip));
    tester.widget<InputChip>(find.byType(InputChip)).onDeleted!();
    await tester.pump();

    response.complete(
      http.Response(
        '<rss><channel><item>'
        '<title>Stale anime story</title>'
        '<link>https://publisher.example/stale-anime</link>'
        '<description>This belongs to the previous interest selection.</description>'
        '<pubDate>Mon, 12 Oct 2026 09:00:00 GMT</pubDate>'
        '<source>Anime News</source>'
        '</item></channel></rss>',
        200,
        headers: {'content-type': 'application/rss+xml; charset=utf-8'},
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Stale anime story'), findsNothing);
    expect(find.byType(InputChip), findsNothing);
    // A response for the removed topic must not repopulate the persistent
    // cache after the interest-change handler has cleared it.
    expect(
      await preferences.getString('omni_ai.news_cache.articles.v1'),
      isNull,
    );
    expect(
      await preferences.getString('omni_ai.news_cache.digest.v1'),
      isNull,
    );
    expect(
      await preferences.getString('omni_ai.news_cache.topics.v1'),
      isNull,
    );
    expect(
      await preferences.getString('omni_ai.news_cache.critical_setting.v1'),
      isNull,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows a visible error when every news edition fails', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repository = _MemoryNewsInterestRepository(
      const NewsInterestProfile(topics: ['anime']),
    );
    var requestCount = 0;
    final service = NewsRssService(
      client: MockClient((_) async {
        requestCount++;
        throw http.ClientException('offline');
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NewsCenterPage(repository: repository, newsService: service),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(requestCount, 3);
    expect(find.textContaining('Не удалось загрузить новости:'), findsOneWidget);
    expect(find.text('ЗАГРУЗКА…'), findsNothing);

    for (
      var i = 0;
      i < 12 && find.text('Диагностика системы').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('Диагностика системы'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.textContaining('RSS-редакции с ошибкой:'),
      findsOneWidget,
    );
    expect(
      find.textContaining('ru-RU: ClientException/network'),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.textContaining('en-US: ClientException/network'),
      findsAtLeastNWidgets(1),
    );
    expect(
      find.textContaining('en-GB: ClientException/network'),
      findsAtLeastNWidgets(1),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('stops loading a generic feed after all interests are removed', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repository = _MemoryNewsInterestRepository(
      const NewsInterestProfile(topics: ['anime']),
    );
    var requestCount = 0;
    final service = NewsRssService(
      client: MockClient((_) async {
        requestCount++;
        return http.Response(
          '<rss><channel><item>'
          '<title>World leaders meet at summit</title>'
          '<link>https://publisher.example/world-summit</link>'
          '<description>Global leaders met today for a summit.</description>'
          '<pubDate>Mon, 12 Oct 2026 09:00:00 GMT</pubDate>'
          '<source>World News</source>'
          '</item></channel></rss>',
          200,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NewsCenterPage(repository: repository, newsService: service),
      ),
    );
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(requestCount, 3);

    final interestsHeading = find.text('ВАШИ ИНТЕРЕСЫ');
    await tester.dragUntilVisible(
      interestsHeading,
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final chip = find.byType(InputChip);
    expect(chip, findsOneWidget);
    tester.widget<InputChip>(chip).onDeleted!();
    await tester.pump();
    await tester.dragUntilVisible(
      find.text('СОХРАНИТЬ ИНТЕРЕСЫ'),
      find.byType(Scrollable).last,
      const Offset(0, -300),
    );
    await tester.tap(find.text('СОХРАНИТЬ ИНТЕРЕСЫ'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(requestCount, 3);
    expect(find.text('World leaders meet at summit'), findsNothing);
    await tester.dragUntilVisible(
      find.textContaining('Общий поток без персонализации не показывается.'),
      find.byType(Scrollable).first,
      const Offset(0, 300),
    );
    expect(
      find.textContaining('Общий поток без персонализации не показывается.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('diagnostics explain partial RSS outages while keeping available news', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repository = _MemoryNewsInterestRepository(
      const NewsInterestProfile(topics: ['anime']),
    );
    final service = _PartiallyFailedNewsRssService();

    await tester.pumpWidget(
      MaterialApp(
        home: NewsCenterPage(repository: repository, newsService: service),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('New anime season announced'), findsOneWidget);
    for (
      var i = 0;
      i < 12 && find.text('Диагностика системы').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('Диагностика системы'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(
      find.textContaining('RSS-редакции с ошибкой: en-US (ClientException)'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Лента частично работает, но некоторые RSS-редакции недоступны.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('diagnostic report explains RSS HTTP status failures', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repository = _MemoryNewsInterestRepository(
      const NewsInterestProfile(topics: ['anime']),
    );
    final service = NewsRssService(
      client: MockClient((_) async => http.Response('upstream unavailable', 503)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NewsCenterPage(repository: repository, newsService: service),
      ),
    );
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.textContaining('Не удалось загрузить новости:'), findsOneWidget);
    for (
      var i = 0;
      i < 12 && find.text('Диагностика системы').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Диагностика системы'), findsOneWidget);
    await tester.tap(find.text('Диагностика системы'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Диагностика OMNI AI'), findsOneWidget);
    expect(find.textContaining('HTTP 503'), findsNWidgets(2));
    expect(
      find.textContaining('RSS-источник вернул HTTP-ошибку'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('diagnostics recommend recovery for RSS timeout and malformed XML', (
    WidgetTester tester,
  ) async {
    Future<void> verifyFailure({
      required http.Client client,
      required String expectedGuidance,
    }) async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final repository = _MemoryNewsInterestRepository(
        const NewsInterestProfile(topics: ['anime']),
      );
      final service = NewsRssService(client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: NewsCenterPage(repository: repository, newsService: service),
        ),
      );
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.textContaining('Не удалось загрузить новости:'), findsOneWidget);
      for (
        var i = 0;
        i < 12 && find.text('Диагностика системы').evaluate().isEmpty;
        i++
      ) {
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Диагностика системы'), findsOneWidget);
      await tester.tap(find.text('Диагностика системы'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Диагностика OMNI AI'), findsOneWidget);
      expect(find.textContaining(expectedGuidance), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }

    await verifyFailure(
      client: MockClient((_) async {
        throw TimeoutException('simulated RSS timeout');
      }),
      expectedGuidance: 'RSS-источник не ответил вовремя',
    );
    await verifyFailure(
      client: MockClient((_) async => http.Response(
        '<html><body>Access denied</body></html>',
        200,
      )),
      expectedGuidance: 'Вместо RSS/XML пришёл ответ другого формата',
    );
  });

  testWidgets('diagnostics report zero RSS candidates and elapsed time for empty editions', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repository = _MemoryNewsInterestRepository(
      const NewsInterestProfile(topics: ['anime']),
    );
    final service = NewsRssService(
      client: MockClient((_) async => http.Response('<rss><channel /></rss>', 200)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NewsCenterPage(repository: repository, newsService: service),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.textContaining('returned no usable articles'), findsOneWidget);
    for (
      var i = 0;
      i < 12 && find.text('Диагностика системы').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('Диагностика системы'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.textContaining('RSS-кандидатов до фильтра: 0'), findsOneWidget);
    expect(find.textContaining('После фильтра интересов: 0'), findsOneWidget);
    expect(find.textContaining('Время RSS: нет данных'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('migrates supported legacy categories into news interests', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repository = _MemoryNewsInterestRepository(
      const NewsInterestProfile(),
    );
    final legacy = UserPreferences()
      ..categories = ['Anime', 'Манга', 'life', 'Telegram'];
    final preferencesStore = _MemoryUserPreferencesStore();
    final service = NewsRssService(
      client: MockClient(
        (_) async => http.Response('<rss><channel /></rss>', 200),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NewsCenterPage(
          repository: repository,
          newsService: service,
          legacyPreferences: legacy,
          preferencesStore: preferencesStore,
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(repository.profile.topics, ['anime', 'manga']);
    expect(legacy.newsInterestsMigrated, isTrue);
    expect(preferencesStore.saved, same(legacy));
    expect(legacy.categories, ['Anime', 'Манга', 'life', 'Telegram']);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('diagnostics explain when topic filtering removes all RSS candidates', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repository = _MemoryNewsInterestRepository(
      const NewsInterestProfile(topics: ['anime']),
    );
    final service = _FilteredOutNewsRssService();

    await tester.pumpWidget(
      MaterialApp(
        home: NewsCenterPage(repository: repository, newsService: service),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.textContaining('По выбранным темам сейчас не найдено'), findsOneWidget);
    for (
      var i = 0;
      i < 12 && find.text('Диагностика системы').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('Диагностика системы'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.textContaining('RSS-кандидатов до фильтра: 5'), findsOneWidget);
    expect(find.textContaining('После фильтра интересов: 0'), findsOneWidget);
    expect(
      find.textContaining('RSS вернул 5 уникальных кандидатов, но фильтр интересов не оставил подходящих публикаций.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('explains why the feed is empty when no interests are selected', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repository = _MemoryNewsInterestRepository(
      const NewsInterestProfile(),
    );
    var requestCount = 0;
    final service = NewsRssService(
      client: MockClient((_) async {
        requestCount++;
        return http.Response('<rss><channel /></rss>', 200);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NewsCenterPage(repository: repository, newsService: service),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // No interests means no generic RSS request and no unpersonalized stories.
    expect(requestCount, 0);
    expect(find.text('НАСТРОИТЬ ИНТЕРЕСЫ'), findsOneWidget);
    expect(
      find.textContaining('Общий поток без персонализации не показывается.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _MemoryNewsInterestRepository implements NewsInterestRepository {
  _MemoryNewsInterestRepository(this.profile);

  NewsInterestProfile profile;

  @override
  Future<NewsInterestProfile> load() async => profile;

  @override
  Future<void> save(NewsInterestProfile nextProfile) async {
    profile = nextProfile;
  }

  @override
  Future<void> dispose() async {}
}


class _PartiallyFailedNewsRssService extends NewsRssService {
  @override
  Future<List<NewsArticle>> fetchInternational(
    NewsInterestProfile profile,
  ) async {
    lastCandidateCount = 1;
    lastRelevantCandidateCount = 1;
    lastFailedEditions = const <String>['en-US (ClientException)'];
    return <NewsArticle>[
      NewsArticle(
        id: 'anime-season',
        title: 'New anime season announced',
        summary: 'A new season was announced.',
        sourceName: 'Anime News',
        sourceUrl: 'https://example.com/anime-season',
        publishedAt: DateTime.utc(2026, 10, 15),
        topics: const <String>['anime'],
      ),
    ];
  }
}

class _FilteredOutNewsRssService extends NewsRssService {
  @override
  Future<List<NewsArticle>> fetchInternational(
    NewsInterestProfile profile,
  ) async {
    lastCandidateCount = 5;
    lastRelevantCandidateCount = 0;
    lastFailedEditions = const <String>[];
    return const <NewsArticle>[];
  }
}

class _MemoryUserPreferencesStore implements UserPreferencesStore {
  UserPreferences? saved;

  @override
  Future<UserPreferences?> load() async => saved;

  @override
  Future<void> save(UserPreferences preferences) async {
    saved = preferences;
  }
}

class _DelayedNewsCacheStore implements NewsCacheStringStore {
  final Completer<void> releaseReads = Completer<void>();

  @override
  Future<String?> read(String key) async {
    await releaseReads.future;
    return null;
  }

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> remove(String key) async {}
}

class _FailingNewsCacheStore implements NewsCacheStringStore {
  @override
  Future<String?> read(String key) async {
    if (key == SharedPreferencesNewsCache.topicsKey) return '["anime"]';
    if (key == SharedPreferencesNewsCache.criticalSettingKey) return 'false';
    return null;
  }

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> remove(String key) async {
    if (key == SharedPreferencesNewsCache.digestKey) {
      throw StateError('Simulated local cache write failure.');
    }
  }
}
