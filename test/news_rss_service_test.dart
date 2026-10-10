import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';
import 'package:omni_ai/features/news/services/news_rss_service.dart';

void main() {
  test('returns only selected-topic RSS articles and removes duplicates', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'news.google.com');
      expect(request.url.path, '/rss/search');
      return http.Response(
        '''
        <rss><channel>
          <item>
            <title>New anime season announced</title>
            <link>https://publisher.example/anime</link>
            <description><![CDATA[<p>A new anime series is coming.</p>]]></description>
            <pubDate>Sat, 10 Oct 2026 12:00:00 GMT</pubDate>
            <source>Anime News</source>
          </item>
          <item>
            <title>New video games announced</title>
            <link>https://publisher.example/games</link>
            <description>Upcoming games</description>
            <pubDate>Sat, 10 Oct 2026 11:00:00 GMT</pubDate>
            <source>Games News</source>
          </item>
          <item>
            <title>Duplicate anime headline</title>
            <link>https://publisher.example/anime</link>
            <description>Anime</description>
            <pubDate>Sat, 10 Oct 2026 10:00:00 GMT</pubDate>
            <source>Anime News</source>
          </item>
        </channel></rss>
        ''',
        200,
        headers: {'content-type': 'application/rss+xml; charset=utf-8'},
      );
    });
    final service = NewsRssService(client: client);
    addTearDown(service.dispose);

    final articles = await service.fetch(
      const NewsInterestProfile(topics: ['anime']),
    );

    expect(articles, hasLength(1));
    expect(articles.single.title, 'New anime season announced');
    expect(articles.single.sourceName, 'Anime News');
    expect(articles.single.summary, contains('A new anime series'));
  });

  test('recognizes Russian-language headlines for selected topics', () async {
    final service = NewsRssService(
      client: MockClient((_) async => http.Response.bytes(
        utf8.encode('''<rss><channel><item>
          <title>Анонсирован новый сезон аниме</title>
          <link>https://publisher.example/ru-anime</link>
          <description>Новости японской анимации</description>
          <pubDate>Sat, 10 Oct 2026 12:00:00 GMT</pubDate>
          <source>Новости аниме</source>
        </item></channel></rss>'''),
        200,
        headers: {'content-type': 'application/rss+xml; charset=utf-8'},
      )),
    );
    addTearDown(service.dispose);

    final articles = await service.fetch(
      const NewsInterestProfile(topics: ['anime']),
    );

    expect(articles, hasLength(1));
    expect(articles.single.topics, contains('anime'));
  });

  test('does not make a network request when no interests are selected', () async {
    var requests = 0;
    final service = NewsRssService(
      client: MockClient((_) async {
        requests++;
        return http.Response('', 200);
      }),
    );
    addTearDown(service.dispose);

    expect(await service.fetch(const NewsInterestProfile()), isEmpty);
    expect(requests, 0);
  });

  test('surfaces source errors instead of inventing news', () async {
    final service = NewsRssService(
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );
    addTearDown(service.dispose);

    expect(
      () => service.fetch(const NewsInterestProfile(topics: ['anime'])),
      throwsA(isA<http.ClientException>()),
    );
  });
}
