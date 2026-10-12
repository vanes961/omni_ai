import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:omni_ai/features/news/data/news_interest_repository.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';
import 'package:omni_ai/features/news/presentation/news_center_page.dart';
import 'package:omni_ai/features/news/services/news_rss_service.dart';

void main() {
  testWidgets(
    'renders real RSS candidates on first visit with saved interests',
    (WidgetTester tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final repository = _MemoryNewsInterestRepository(
        const NewsInterestProfile(topics: ['anime']),
      );
      var requestCount = 0;
      final service = NewsRssService(
        client: MockClient(
          (_) async {
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
          },
        ),
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
      expect(find.text('Anime News'), findsOneWidget);
      expect(find.text('Не удалось загрузить новости.'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
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
