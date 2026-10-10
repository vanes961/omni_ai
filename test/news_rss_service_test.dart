import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';
import 'package:omni_ai/features/news/services/news_rss_service.dart';

void main() {
  test('deduplicates tracking URL variants and keeps the newest story', () async {
    final service = NewsRssService(
      client: MockClient((_) async => http.Response(
        '''<rss><channel>
          <item>
            <title>Anime: New season!</title>
            <link>https://publisher.example/story?utm_source=ru#top</link>
            <description>Earlier summary</description>
            <pubDate>Sat, 10 Oct 2026 10:00:00 GMT</pubDate>
            <source>Publisher</source>
          </item>
          <item>
            <title>Anime — New season</title>
            <link>https://publisher.example/story?utm_source=en&amp;fbclid=tracking</link>
            <description>The latest summary from the publisher.</description>
            <pubDate>Sat, 10 Oct 2026 12:00:00 GMT</pubDate>
            <source>Publisher</source>
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
    expect(articles.single.title, 'Anime — New season');
    expect(articles.single.summary, 'The latest summary from the publisher.');
    // Keep the publisher's original link for the user; only the dedupe key is
    // canonicalized, so attribution and navigation remain unchanged.
    expect(
      articles.single.sourceUrl,
      'https://publisher.example/story?utm_source=en&fbclid=tracking',
    );
  });

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

  test('deduplicates tracking URL variants across international editions', () async {
    final service = NewsRssService(
      client: MockClient((request) async {
        final language = request.url.queryParameters['hl'];
        final region = request.url.queryParameters['gl'];
        final isRussian = language == 'ru';
        final isUs = region == 'US';
        final title = isRussian
            ? 'Анонсирован новый сезон аниме'
            : 'New anime season announced';
        final link = isRussian
            ? 'https://publisher.example/story?utm_source=ru#top'
            : 'https://publisher.example/story?utm_source=$region&amp;fbclid=tracking';
        final date = isRussian
            ? 'Sat, 10 Oct 2026 10:00:00 GMT'
            : isUs
                ? 'Sat, 10 Oct 2026 12:00:00 GMT'
                : 'Sat, 10 Oct 2026 11:00:00 GMT';
        return http.Response(
          '''<rss><channel><item>
            <title>$title</title>
            <link>$link</link>
            <description>Anime news update from the $region edition</description>
            <pubDate>$date</pubDate>
            <source>News source</source>
          </item></channel></rss>''',
          200,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        );
      }),
    );
    addTearDown(service.dispose);

    final articles = await service.fetchInternational(
      const NewsInterestProfile(topics: ['anime']),
    );

    expect(articles, hasLength(1));
    expect(articles.single.title, 'New anime season announced');
    expect(articles.single.language, 'en');
    expect(articles.single.region, 'us');
    expect(articles.single.publishedAt, DateTime.utc(2026, 10, 10, 12));
    // The comparison URL is normalized, but navigation keeps the source URL.
    expect(
      articles.single.sourceUrl,
      'https://publisher.example/story?utm_source=US&fbclid=tracking',
    );
  });

  test('keeps repeated URL query values distinct during deduplication', () async {
    final service = NewsRssService(
      client: MockClient((_) async => http.Response(
        '''<rss><channel>
          <item>
            <title>Anime story with comma tag</title>
            <link>https://publisher.example/story?tag=a%2Cb&amp;tag=c</link>
            <description>Anime news</description>
            <pubDate>Sat, 10 Oct 2026 12:00:00 GMT</pubDate>
            <source>Anime News</source>
          </item>
          <item>
            <title>Anime story with split tags</title>
            <link>https://publisher.example/story?tag=a&amp;tag=b%2Cc</link>
            <description>Anime news</description>
            <pubDate>Sat, 10 Oct 2026 11:00:00 GMT</pubDate>
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

    expect(articles, hasLength(2));
    expect(
      articles.map((article) => article.sourceUrl),
      containsAll([
        'https://publisher.example/story?tag=a%2Cb&tag=c',
        'https://publisher.example/story?tag=a&tag=b%2Cc',
      ]),
    );
  });

  test('reports an error when all international news editions fail', () async {
    final service = NewsRssService(
      client: MockClient((request) async {
        final region = request.url.queryParameters['gl'];
        throw http.ClientException('Edition $region unavailable');
      }),
    );
    addTearDown(service.dispose);

    expect(
      service.fetchInternational(
        const NewsInterestProfile(topics: ['anime']),
      ),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('keeps other editions when one international RSS source fails', () async {
    final service = NewsRssService(
      client: MockClient((request) async {
        final language = request.url.queryParameters['hl'];
        final region = request.url.queryParameters['gl'];
        if (region == 'US') {
          throw Exception('US edition unavailable');
        }
        final isRussian = language == 'ru';
        return http.Response(
          '''<rss><channel><item>
            <title>${isRussian ? 'Новый сезон аниме' : 'New anime season announced'}</title>
            <link>https://publisher.example/anime-$region</link>
            <description>Anime news update</description>
            <pubDate>Sat, 10 Oct 2026 12:00:00 GMT</pubDate>
            <source>News source</source>
          </item></channel></rss>''',
          200,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        );
      }),
    );
    addTearDown(service.dispose);

    final articles = await service.fetchInternational(
      const NewsInterestProfile(topics: ['anime']),
    );

    expect(articles, hasLength(2));
    expect(articles.map((article) => article.region), containsAll(['ru', 'gb']));
  });

  test('fetches international editions and filters topics without locale lock', () async {
    var requests = 0;
    final service = NewsRssService(
      client: MockClient((request) async {
        requests++;
        final language = request.url.queryParameters['hl'];
        final region = request.url.queryParameters['gl'];
        expect(
          <String>{'ru:RU', 'en:US', 'en:GB'},
          contains('$language:$region'),
        );
        final isRussian = language == 'ru';
        final title = isRussian
            ? 'Новый сезон аниме объявлен'
            : 'New anime season announced';
        final link = isRussian
            ? 'https://publisher.example/ru-anime'
            : 'https://publisher.example/en-anime-$region';
        return http.Response(
          '''<rss><channel><item>
            <title>$title</title>
            <link>$link</link>
            <description>Anime news update</description>
            <pubDate>Sat, 10 Oct 2026 12:00:00 GMT</pubDate>
            <source>News source</source>
          </item></channel></rss>''',
          200,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        );
      }),
    );
    addTearDown(service.dispose);

    final articles = await service.fetchInternational(
      const NewsInterestProfile(topics: ['anime']),
    );

    expect(requests, 3);
    expect(articles.map((article) => article.language), contains('ru'));
    expect(articles.map((article) => article.language), contains('en'));
    expect(articles, hasLength(2));
  });

  test('normalizes common topic aliases before querying and filtering', () async {
    final service = NewsRssService(
      client: MockClient((request) async {
        expect(
          request.url.queryParameters['q'],
          'artificial intelligence AI',
        );
        return http.Response(
          '''<rss><channel><item>
            <title>New artificial intelligence model announced</title>
            <link>https://publisher.example/ai-alias</link>
            <description>AI and neural network research update</description>
            <pubDate>Sat, 10 Oct 2026 12:00:00 GMT</pubDate>
            <source>Technology News</source>
          </item></channel></rss>''',
          200,
        );
      }),
    );
    addTearDown(service.dispose);

    final articles = await service.fetch(
      const NewsInterestProfile(topics: [' AI ']),
    );

    expect(articles, hasLength(1));
    expect(articles.single.topics, contains('artificial intelligence'));
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

  test('normalizes selected topic names before building the RSS query', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['q'], 'anime OR technology');
      return http.Response(
        '''<rss><channel><item>
          <title>New anime season announced</title>
          <link>https://publisher.example/normalized-topic</link>
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
      const NewsInterestProfile(topics: [' Anime ', 'technology', 'ANIME']),
    );

    expect(articles, hasLength(1));
    expect(articles.single.topics, contains('anime'));
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

  test('does not make a network request when selected topics are blank', () async {
    var requests = 0;
    final service = NewsRssService(
      client: MockClient((_) async {
        requests++;
        return http.Response('', 200);
      }),
    );
    addTearDown(service.dispose);

    expect(
      await service.fetch(const NewsInterestProfile(topics: [' ', '  '])),
      isEmpty,
    );
    expect(requests, 0);
  });


  test('keeps news from healthy editions when one international edition fails', () async {
    var requests = 0;
    final service = NewsRssService(
      client: MockClient((request) async {
        requests++;
        final region = request.url.queryParameters['gl'];
        if (region == 'US') {
          throw http.ClientException('Simulated unavailable edition');
        }
        return http.Response(
          '''<rss><channel><item>
            <title>Anime update from $region</title>
            <link>https://publisher.example/anime-$region</link>
            <description>Anime news update from the $region edition</description>
            <pubDate>Sat, 10 Oct 2026 12:00:00 GMT</pubDate>
            <source>News source</source>
          </item></channel></rss>''',
          200,
          headers: {'content-type': 'application/rss+xml; charset=utf-8'},
        );
      }),
    );
    addTearDown(service.dispose);

    final articles = await service.fetchInternational(
      const NewsInterestProfile(topics: ['anime']),
    );

    expect(requests, 3);
    expect(articles, hasLength(2));
    expect(articles.map((article) => article.region), containsAll(['ru', 'gb']));
    expect(articles.map((article) => article.region), isNot(contains('us')));
  });

}
