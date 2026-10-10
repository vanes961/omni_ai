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
      expect(request.url.queryParameters['q'], 'anime');
      expect(request.url.queryParameters['hl'], 'ru');
      expect(request.url.queryParameters['gl'], 'RU');
      expect(request.url.queryParameters['ceid'], 'RU:ru');
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

  test('matches the Russian AI abbreviation only as a whole word', () async {
    final service = NewsRssService(
      client: MockClient((_) async => http.Response(
        '''<rss><channel>
          <item>
            <title>Новости России за сегодня</title>
            <link>https://publisher.example/russia</link>
            <description>Главные события в России</description>
            <pubDate>Sat, 10 Oct 2026 12:00:00 GMT</pubDate>
            <source>Новости</source>
          </item>
          <item>
            <title>Новые модели ИИ прошли испытания</title>
            <link>https://publisher.example/ai</link>
            <description>Развитие ИИ и нейросетей</description>
            <pubDate>Sat, 10 Oct 2026 11:00:00 GMT</pubDate>
            <source>Новости технологий</source>
          </item>
        </channel></rss>''',
        200,
        headers: {'content-type': 'application/rss+xml; charset=utf-8'},
      )),
    );
    addTearDown(service.dispose);

    final articles = await service.fetch(
      const NewsInterestProfile(topics: ['artificial intelligence']),
    );

    expect(articles, hasLength(1));
    expect(articles.single.sourceUrl, 'https://publisher.example/ai');
    expect(articles.single.topics, contains('artificial intelligence'));
  });

  test('preserves the selected region so region filtering keeps RSS articles', () async {
    final service = NewsRssService(
      client: MockClient((_) async => http.Response.bytes(
        utf8.encode('''<rss><channel><item>
          <title>Анонсирован новый сезон аниме</title>
          <link>https://publisher.example/region-anime</link>
          <description>Новости аниме</description>
          <pubDate>Sat, 10 Oct 2026 12:00:00 GMT</pubDate>
          <source>Новости аниме</source>
        </item></channel></rss>'''),
        200,
        headers: {'content-type': 'application/rss+xml; charset=utf-8'},
      )),
    );
    addTearDown(service.dispose);

    final articles = await service.fetch(
      const NewsInterestProfile(topics: ['anime'], regions: ['ru']),
    );

    expect(articles, hasLength(1));
    expect(articles.single.region, 'ru');
  });

  test('uses the selected language and region in the RSS request', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['q'], 'anime');
      expect(request.url.queryParameters['hl'], 'en');
      expect(request.url.queryParameters['gl'], 'US');
      expect(request.url.queryParameters['ceid'], 'US:en');
      return http.Response(
        '''<rss><channel><item>
          <title>New anime season announced</title>
          <link>https://publisher.example/en-anime</link>
          <description>A new anime series is coming.</description>
          <pubDate>Sat, 10 Oct 2026 12:00:00 GMT</pubDate>
          <source>Anime News</source>
        </item></channel></rss>''',
        200,
      );
    });
    final service = NewsRssService(client: client);
    addTearDown(service.dispose);

    final articles = await service.fetch(
      const NewsInterestProfile(
        topics: ['anime'],
        languages: ['en'],
        regions: ['us'],
      ),
    );

    expect(articles, hasLength(1));
    expect(articles.single.language, 'en');
    expect(articles.single.region, 'us');
  });

  test('ignores RSS items with invalid links or missing publication dates', () async {
    final service = NewsRssService(
      client: MockClient((_) async => http.Response(
        '''<rss><channel>
          <item>
            <title>Anime without a publication date</title>
            <link>https://publisher.example/no-date</link>
            <description>Anime news</description>
            <source>Anime News</source>
          </item>
          <item>
            <title>Anime with an unsafe link</title>
            <link>javascript:alert(1)</link>
            <description>Anime news</description>
            <pubDate>Sat, 10 Oct 2026 12:00:00 GMT</pubDate>
            <source>Anime News</source>
          </item>
          <item>
            <title>Valid anime publication</title>
            <link>https://publisher.example/valid-anime</link>
            <description>Anime news</description>
            <pubDate>Sat, 10 Oct 2026 12:00:00 GMT</pubDate>
            <source>Anime News</source>
          </item>
        </channel></rss>''',
        200,
        headers: {'content-type': 'application/rss+xml; charset=utf-8'},
      )),
    );
    addTearDown(service.dispose);

    final articles = await service.fetch(
      const NewsInterestProfile(topics: ['anime']),
    );

    expect(articles, hasLength(1));
    expect(articles.single.sourceUrl, 'https://publisher.example/valid-anime');
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

  test('normalizes whitespace and case in selected locale parameters', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['hl'], 'en');
      expect(request.url.queryParameters['gl'], 'US');
      expect(request.url.queryParameters['ceid'], 'US:en');
      return http.Response(
        '''<rss><channel><item>
          <title>New anime season announced</title>
          <link>https://publisher.example/normalized-locale</link>
          <description>A new anime series is coming.</description>
          <pubDate>Sat, 10 Oct 2026 12:00:00 GMT</pubDate>
          <source>Anime News</source>
        </item></channel></rss>''',
        200,
      );
    });
    final service = NewsRssService(client: client);
    addTearDown(service.dispose);

    final articles = await service.fetch(
      const NewsInterestProfile(
        topics: ['anime'],
        languages: ['  ', ' EN '],
        regions: [' ', ' us '],
      ),
    );

    expect(articles, hasLength(1));
    expect(articles.single.language, 'en');
    expect(articles.single.region, 'us');
  });

  test('ignores malformed RSS items and decodes escaped text safely', () async {
    final service = NewsRssService(
      client: MockClient((_) async => http.Response(
        '''<rss><channel>
          <item>
            <title>Anime &#38; manga &#x1F3AE; news</title>
            <link>https://publisher.example/escaped</link>
            <description>Anime &#x2014; manga &#38; &#x3C;updates&#x3E;</description>
            <pubDate>Sat, 10 Oct 2026 12:00:00 GMT</pubDate>
          </item>
          <item>
            <title>Anime with an invalid date</title>
            <link>https://publisher.example/invalid-date</link>
            <description>Anime news</description>
            <pubDate>not-a-date</pubDate>
          </item>
          <item>
            <title>Incomplete item without a closing tag
          </item>
        </channel></rss>''',
        200,
        headers: {'content-type': 'application/rss+xml; charset=utf-8'},
      )),
    );
    addTearDown(service.dispose);

    final articles = await service.fetch(
      const NewsInterestProfile(topics: ['anime']),
    );

    expect(articles, hasLength(1));
    expect(articles.single.title, 'Anime & manga 🎮 news');
    expect(articles.single.summary, 'Anime — manga & updates');
    expect(articles.single.sourceName, 'publisher.example');
  });
}
