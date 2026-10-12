import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:omni_ai/features/news/data/news_interest_repository.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';
import 'package:omni_ai/features/news/presentation/news_center_page.dart';
import 'package:omni_ai/features/news/services/news_rss_service.dart';

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
    expect(find.textContaining('ANIME NEWS'), findsOneWidget);
    expect(find.text('Не удалось загрузить новости.'), findsNothing);
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
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(requestCount, 0);
    expect(
      find.textContaining('без выбранных тем'),
      findsOneWidget,
    );
    expect(find.text('НАСТРОИТЬ ИНТЕРЕСЫ'), findsOneWidget);
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
