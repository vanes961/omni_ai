import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:omni_ai/features/news/models/news_article.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';
import 'package:omni_ai/features/news/services/news_relevance_filter.dart';

/// The failure class identifies the stage that prevented an RSS request from
/// producing usable data, without retaining response bodies or credentials.
enum NewsRssFailureKind {
  timeout,
  network,
  httpStatus,
  emptyResponse,
  malformedRss,
}

class NewsRssException extends http.ClientException {
  NewsRssException({
    required this.kind,
    required String message,
    this.statusCode,
    Uri? uri,
  }) : super(message, uri);

  final NewsRssFailureKind kind;
  final int? statusCode;
}

/// Reads public Google News RSS feeds and search results. No API key is embedded in the
/// application. RSS excerpts are displayed with source attribution; full
/// publisher articles remain at their original source.
class NewsRssService {
  NewsRssService({http.Client? client, NewsRelevanceFilter? filter})
    : _client = client ?? http.Client(),
      _filter = filter ?? const NewsRelevanceFilter();

  final http.Client _client;
  final NewsRelevanceFilter _filter;

  /// Number of unique, parsed RSS candidates before strict topic filtering.
  /// Null means an international fetch has not completed its parsing stage.
  int? lastCandidateCount;

  /// Number of candidates remaining after strict topic relevance filtering.
  int? lastRelevantCandidateCount;

  /// Failed international editions from the most recent fetch.
  List<String> lastFailedEditions = const <String>[];

  static const _topicKeywords = <String, List<String>>{
    'games': ['game', 'gaming', 'video game', 'игр', 'гейминг'],
    'anime': ['anime', 'аниме'],
    'manga': ['manga', 'манга'],
    'movies': ['movie', 'movies', 'cinema', 'film', 'кино', 'фильм'],
    'series': ['series', 'tv series', 'streaming', 'сериал', 'сериалы'],
    'technology': ['technology', 'tech', 'технолог', 'техника'],
    'artificial intelligence': [
      'artificial intelligence',
      ' ai ',
      'ии',
      'искусственн',
      'нейросет',
    ],
    'science': ['science', 'scientific', 'наук', 'исследован'],
    'space': [
      'space',
      'astronomy',
      'spaceflight',
      'космос',
      'астроном',
      'космич',
    ],
    'gadgets': [
      'gadget',
      'electronics',
      'smartphone',
      'гаджет',
      'смартфон',
      'электроник',
    ],
  };

  // Only high-impact public-safety events bypass topic preferences, and only
  // when the user explicitly enables critical news in their profile.
  static const _criticalNewsKeywords = <String>[
    'state of emergency',
    'emergency declared',
    'major earthquake',
    'earthquake of magnitude',
    'tsunami warning',
    'evacuation order',
    'mass casualty',
    'critical infrastructure outage',
    'national emergency',
    'terrorist attack',
    'major wildfire',
    'severe flooding',
    'чрезвычайное положение',
    'режим чс',
    'объявлена эвакуация',
    'угроза цунами',
    'землетрясение магнитудой',
    'крупное землетрясение',
    'массовая гибель',
    'теракт',
    'крупный пожар',
    'масштабное наводнение',
    'авария на атомной станции',
    'радиационная авария',
  ];

  bool _isCriticalNews(String text) {
    final normalized = ' ${text.toLowerCase()} ';
    return _criticalNewsKeywords.any(
      (keyword) => _containsKeyword(normalized, keyword),
    );
  }

  static const _topicQueries = <String, String>{
    'games': 'video games gaming',
    'anime': 'anime',
    'manga': 'manga',
    'movies': 'movies cinema',
    'series': 'TV series streaming',
    'technology': 'technology',
    'artificial intelligence': 'artificial intelligence AI',
    'science': 'science',
    'space': 'space exploration astronomy',
    'gadgets': 'gadgets consumer electronics',
  };

  /// Public Russian-language RSS sources. The app shows only the feed's
  /// title/excerpt with source attribution and opens the publisher for the
  /// full article; commercial redistribution still requires checking each
  /// publisher's terms or obtaining permission where required.
  static const _russianRssSources = <Map<String, String>>[
    {'name': 'Лента.ру', 'url': 'https://lenta.ru/rss'},
    {'name': 'Вести', 'url': 'https://www.vesti.ru/vesti.rss'},
    {'name': 'Московский комсомолец', 'url': 'https://www.mk.ru/rss/index.xml'},
    {'name': 'Российская газета', 'url': 'https://rg.ru/xml/index.xml'},
    {'name': 'Хабр', 'url': 'https://habr.com/ru/rss/all/all/?fl=ru'},
    {'name': 'Банк России: новости', 'url': 'https://www.cbr.ru/rss/RssNews'},
    {'name': 'Банк России: события', 'url': 'https://www.cbr.ru/rss/eventrss'},
    {'name': 'Газета.Ru', 'url': 'https://www.gazeta.ru/export/rss/first.xml'},
    {'name': 'Известия', 'url': 'https://iz.ru/xml/rss/all.xml'},
    {'name': 'РИА Новости', 'url': 'https://ria.ru/export/rss2/index.xml'},
    {'name': 'Москва 24', 'url': 'https://www.m24.ru/rss.xml'},
    {
      'name': 'Минфин России',
      'url': 'https://minfin.gov.ru/ru/press-center/rss/',
    },
    {'name': 'Росстат', 'url': 'https://rosstat.gov.ru/rss'},
  ];

  Future<List<NewsArticle>> _fetchRussianRssSources() async {
    final batches = await Future.wait(
      _russianRssSources.map((source) async {
        final uri = Uri.parse(source['url']!);
        try {
          final response = await _client
              .get(uri, headers: const {'User-Agent': 'OMNI-AI-News/1.0'})
              .timeout(const Duration(seconds: 12));
          if (response.statusCode != 200) return const <NewsArticle>[];
          final xml = utf8
              .decode(response.bodyBytes, allowMalformed: true)
              .trim();
          if (xml.isEmpty ||
              !RegExp(r'<rss\b', caseSensitive: false).hasMatch(xml)) {
            return const <NewsArticle>[];
          }
          return _parseItems(
            xml,
            'ru',
            'ru',
            defaultSourceName: source['name']!,
          );
        } on Object {
          // A single unavailable publisher must not blank the whole feed.
          return const <NewsArticle>[];
        }
      }),
    );
    return batches.expand((batch) => batch).toList(growable: false);
  }

  /// Collects candidates from Russian and English Google News editions.
  /// Edition locale describes the feed, not the article's actual geography.
  Future<List<NewsArticle>> fetchInternational(
    NewsInterestProfile profile,
  ) async {
    lastCandidateCount = null;
    lastRelevantCandidateCount = null;
    lastFailedEditions = const <String>[];
    const locales = <List<String>>[
      ['ru', 'RU'],
      ['en', 'US'],
      ['en', 'GB'],
    ];
    var successfulEditions = 0;
    final failedEditions = <String>[];
    final batches = await Future.wait(
      locales.map((locale) async {
        try {
          final localizedProfile = profile.copyWith(
            languages: <String>[locale[0]],
            regions: <String>[locale[1]],
          );
          final hasTopics = localizedProfile.topics.any(
            (topic) => topic.trim().isNotEmpty,
          );
          final articles = <NewsArticle>[];
          final profilesToFetch =
              !hasTopics && localizedProfile.includeCriticalOutsideInterests
              ? <NewsInterestProfile>[
                  localizedProfile.copyWith(
                    includeCriticalOutsideInterests: false,
                  ),
                  localizedProfile,
                ]
              : <NewsInterestProfile>[localizedProfile];
          Object? firstFailure;
          for (final editionProfile in profilesToFetch) {
            try {
              articles.addAll(
                await fetch(editionProfile, applyRelevanceFilter: false),
              );
            } catch (error) {
              // Preserve any usable discovery or critical results when the
              // companion query fails for this edition.
              firstFailure ??= error;
            }
          }
          if (articles.isEmpty && firstFailure != null) {
            throw firstFailure;
          }
          successfulEditions++;
          return articles;
        } catch (error) {
          // One unavailable edition should not block the remaining sources.
          // Keep only locale and error type so diagnostics remain useful
          // without exposing response bodies or arbitrary network payloads.
          failedEditions.add(
            '${locale[0]}-${locale[1]}: ${_failureSummary(error)}',
          );
          lastFailedEditions = List<String>.unmodifiable(failedEditions);
          return const <NewsArticle>[];
        }
      }),
    );
    // Russian publisher feeds are a fallback, not an additional batch on
    // every refresh. This keeps normal refreshes fast and avoids treating
    // unrelated publisher outages as failures of the three Google editions.
    var allBatches = <List<NewsArticle>>[...batches];
    if (successfulEditions == 0) {
      final russianArticles = await _fetchRussianRssSources();
      if (russianArticles.isEmpty) {
        throw http.ClientException(
          'All Russian and international news sources are unavailable '
          '(${failedEditions.join(', ')}).',
        );
      }
      allBatches = <List<NewsArticle>>[...batches, russianArticles];
    }
    // A nominally successful HTTP response can still contain no usable RSS
    // items. Never turn an all-empty result into a silent blank feed: report
    // whether the likely cause is a partial outage or empty source responses.
    if (allBatches.every((batch) => batch.isEmpty)) {
      lastCandidateCount = 0;
      lastRelevantCandidateCount = 0;
      if (failedEditions.isNotEmpty) {
        throw http.ClientException(
          'No articles were returned and some international news editions '
          'failed (${failedEditions.join(', ')}).',
        );
      }
      throw http.ClientException(
        'International news sources returned no usable articles.',
      );
    }

    final byUrl = <String, NewsArticle>{};
    for (final article in allBatches.expand((batch) => batch)) {
      // Apply the same tracking-parameter normalization across editions as
      // within a single feed, while retaining the original user-facing URL.
      final url = _canonicalUrl(article.sourceUrl);
      if (url.isEmpty) continue;
      final previous = byUrl[url];
      if (previous == null || _preferArticle(article, previous)) {
        byUrl[url] = article;
      }
    }

    // Different editions can repeat a headline with tracking URLs.
    final byTitle = <String, NewsArticle>{};
    for (final article in byUrl.values) {
      final titleKey = _normalizedTitle(article.title);
      if (titleKey.isEmpty) continue;
      final previous = byTitle[titleKey];
      if (previous == null || _preferArticle(article, previous)) {
        byTitle[titleKey] = article;
      }
    }

    lastCandidateCount = byTitle.length;
    final unrestrictedProfile = profile.copyWith(
      topics: profile.topics
          .map(_canonicalTopic)
          .where((topic) => topic.isNotEmpty)
          .toSet()
          .toList(growable: false),
      languages: const <String>[],
      regions: const <String>[],
    );
    if (unrestrictedProfile.topics.isEmpty) {
      final articles = List<NewsArticle>.unmodifiable(
        byTitle.values.toList()
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt)),
      );
      lastRelevantCandidateCount = articles.length;
      return articles;
    }
    final relevant = _filter.filter(byTitle.values, unrestrictedProfile);
    lastRelevantCandidateCount = relevant.length;
    return relevant;
  }

  Future<List<NewsArticle>> fetch(
    NewsInterestProfile profile, {
    bool applyRelevanceFilter = true,
  }) async {
    final isDiscoveryFeed =
        profile.topics.every((topic) => topic.trim().isEmpty) &&
        !profile.includeCriticalOutsideInterests;
    final language = profile.languages
        .map((value) => value.trim().toLowerCase())
        .firstWhere((value) => value.isNotEmpty, orElse: () => 'ru');
    final region = profile.regions
        .map((value) => value.trim().toUpperCase())
        .firstWhere((value) => value.isNotEmpty, orElse: () => 'RU');
    final canonicalTopics = profile.topics
        .map(_canonicalTopic)
        .where((topic) => topic.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final topicQuery = canonicalTopics
        .map((topic) => _topicQueries[topic] ?? topic)
        .join(' OR ');
    final criticalQuery = profile.includeCriticalOutsideInterests
        ? _criticalNewsKeywords.map((keyword) => '"$keyword"').join(' OR ')
        : '';
    final query = isDiscoveryFeed
        ? 'news'
        : topicQuery.isEmpty
        ? criticalQuery
        : criticalQuery.isEmpty
        ? topicQuery
        : '($topicQuery) OR ($criticalQuery)';
    final canonicalProfile = profile.copyWith(topics: canonicalTopics);
    if (query.isEmpty && !isDiscoveryFeed) {
      return const <NewsArticle>[];
    }
    // With no selected interests, use the edition's top-stories feed rather
    // than searching for the literal word "news". The latter biases discovery
    // toward headlines that happen to contain that word and can hide ordinary
    // current-affairs headlines from the user's feed.
    final uri =
        Uri.https('news.google.com', isDiscoveryFeed ? '/rss' : '/rss/search', {
          if (!isDiscoveryFeed) 'q': query,
          'hl': language == 'ru' ? 'ru' : language,
          'gl': region,
          'ceid': '$region:$language',
        });
    late final http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'User-Agent': 'OMNI-AI-News/1.0'})
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw NewsRssException(
        kind: NewsRssFailureKind.timeout,
        message: 'News source request timed out after 20 seconds.',
        uri: uri,
      );
    } on SocketException {
      throw NewsRssException(
        kind: NewsRssFailureKind.network,
        message: 'News source network connection failed.',
        uri: uri,
      );
    } on http.ClientException catch (error) {
      throw NewsRssException(
        kind: NewsRssFailureKind.network,
        message: 'News source request failed: ${error.runtimeType}.',
        uri: uri,
      );
    }
    if (response.statusCode != 200) {
      throw NewsRssException(
        kind: NewsRssFailureKind.httpStatus,
        statusCode: response.statusCode,
        message: 'News source returned HTTP ${response.statusCode}.',
        uri: uri,
      );
    }

    final xml = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (xml.isEmpty) {
      throw NewsRssException(
        kind: NewsRssFailureKind.emptyResponse,
        message: 'News source returned an empty response body.',
        uri: uri,
      );
    }
    if (!RegExp(r'<rss\b', caseSensitive: false).hasMatch(xml)) {
      throw NewsRssException(
        kind: NewsRssFailureKind.malformedRss,
        message: 'News source response is not recognizable RSS XML.',
        uri: uri,
      );
    }
    final articles = _parseItems(
      xml,
      language,
      region.toLowerCase(),
      selectedTopics: canonicalTopics,
    );
    final unique = <String, NewsArticle>{};
    for (final article in articles) {
      final key = _canonicalUrl(article.sourceUrl);
      if (key.isEmpty) continue;
      final previous = unique[key];
      if (previous == null || _preferArticle(article, previous)) {
        unique[key] = article;
      }
    }
    if (!applyRelevanceFilter) {
      final candidates = unique.values.toList(growable: false)
        ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      return List<NewsArticle>.unmodifiable(candidates);
    }
    if (isDiscoveryFeed) {
      return List<NewsArticle>.unmodifiable(
        unique.values.toList()
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt)),
      );
    }
    return _filter.filter(unique.values, canonicalProfile);
  }

  /// Removes common tracking parameters without changing the URL shown to
  /// the user. This lets editions deduplicate the same story when publishers
  /// append campaign IDs or fragments to an otherwise identical link.
  String _canonicalUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return '';
    const trackingKeys = <String>{
      'fbclid',
      'gclid',
      'dclid',
      'mc_cid',
      'mc_eid',
      'ref',
      'ref_src',
      'source',
    };
    final kept =
        uri.queryParametersAll.entries.where((entry) {
          final key = entry.key.toLowerCase();
          return !key.startsWith('utm_') && !trackingKeys.contains(key);
        }).toList()..sort((a, b) {
          final byKey = a.key.toLowerCase().compareTo(b.key.toLowerCase());
          return byKey != 0
              ? byKey
              : a.value.join(',').compareTo(b.value.join(','));
        });
    final query = <String, dynamic>{
      for (final entry in kept) entry.key: entry.value,
    };
    return uri
        .replace(
          fragment: '',
          query: query.isEmpty ? '' : null,
          queryParameters: query.isEmpty ? null : query,
          path: uri.path.isEmpty ? '/' : uri.path,
        )
        .toString();
  }

  String _canonicalTopic(String topic) {
    final normalized = topic.trim().toLowerCase();
    return switch (normalized) {
      'ai' || 'ии' || 'нейросети' => 'artificial intelligence',
      'tech' || 'technology news' => 'technology',
      'gaming' || 'video games' => 'games',
      'cinema' || 'film' || 'films' => 'movies',
      'tv' || 'tv series' => 'series',
      _ => normalized,
    };
  }

  String _normalizedTitle(String title) => title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'''[.,!?;:()\[\]{}"'«»—–-]'''), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _preferArticle(NewsArticle candidate, NewsArticle current) {
    if (candidate.publishedAt.isAfter(current.publishedAt)) return true;
    if (candidate.publishedAt.isBefore(current.publishedAt)) return false;
    if (candidate.summary.trim().length != current.summary.trim().length) {
      return candidate.summary.trim().length > current.summary.trim().length;
    }
    return candidate.isVerified && !current.isVerified;
  }

  List<NewsArticle> _parseItems(
    String xml,
    String language,
    String? profileRegion, {
    List<String> selectedTopics = const <String>[],
    String? defaultSourceName,
  }) {
    final items = RegExp(
      r'<item(?:\s[^>]*)?>([\s\S]*?)</item>',
      caseSensitive: false,
    ).allMatches(xml);
    // Only use the query-based fallback when none of the returned items
    // can be matched to the selected interests. Otherwise an unrelated item
    // in a mixed RSS response could inherit the selected topics.
    final hasSelectedTopicMatch = items.any((match) {
      final item = match.group(1) ?? '';
      final title = _tag(item, 'title');
      final link = _tag(item, 'link');
      final published =
          _parseDate(_tag(item, 'pubDate')) ??
          _parseDate(_tag(item, 'dc:date'));
      final uri = Uri.tryParse(link);
      // Invalid RSS items must not suppress query-based topic fallback for
      // otherwise valid results later in the same response.
      if (title.isEmpty ||
          link.isEmpty ||
          published == null ||
          uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty) {
        return false;
      }
      final description = _stripMarkup(
        _tag(item, 'description', decodeEntities: false),
      );
      final normalized =
          ' ${title.toLowerCase()} ${description.toLowerCase()} ';
      return selectedTopics.any((topic) {
        final keywords = _topicKeywords[topic];
        if (keywords != null) {
          return keywords.any(
            (keyword) => _containsKeyword(normalized, keyword),
          );
        }
        return _containsKeyword(normalized, topic);
      });
    });
    final result = <NewsArticle>[];
    for (final match in items) {
      final item = match.group(1) ?? '';
      final title = _tag(item, 'title');
      final link = _tag(item, 'link');
      final description = _tag(item, 'description', decodeEntities: false);
      final published =
          _parseDate(_tag(item, 'pubDate')) ??
          _parseDate(_tag(item, 'dc:date'));
      if (title.isEmpty || link.isEmpty || published == null) continue;
      final uri = Uri.tryParse(link);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
      final sourceName = _tag(item, 'source').isNotEmpty
          ? _tag(item, 'source')
          : (defaultSourceName ?? uri.host);
      final text = _stripMarkup(description);
      final normalized = ' ${title.toLowerCase()} ${text.toLowerCase()} ';
      final detectedTopics = _topicKeywords.entries
          .where(
            (entry) => entry.value.any(
              (keyword) => _containsKeyword(normalized, keyword),
            ),
          )
          .map((entry) => entry.key)
          .toSet();
      // User-defined interests must remain usable even when they are not one
      // of the built-in topic categories. Otherwise RSS can return relevant
      // results that the strict relevance filter silently drops.
      for (final topic in selectedTopics) {
        if (!_topicKeywords.containsKey(topic) &&
            _containsKeyword(normalized, topic)) {
          detectedTopics.add(topic);
        }
      }
      final isCritical = _isCriticalNews('$title $text');
      // Google News already searched the selected topic query. If the
      // entire response lacks detectable selected-topic keywords, preserve
      // the query-matched results. Do not apply this fallback item by item:
      // that would also admit unrelated items from a mixed response.
      if (!hasSelectedTopicMatch && !isCritical) {
        detectedTopics.addAll(selectedTopics);
      }
      final topics = detectedTopics.toList(growable: false);
      result.add(
        NewsArticle(
          id: uri.toString(),
          title: title,
          summary: text,
          sourceName: sourceName,
          sourceUrl: uri.toString(),
          publishedAt: published.toUtc(),
          topics: topics,
          language: language,
          isCritical: isCritical,
          region: profileRegion,
          isVerified: true,
        ),
      );
    }
    return result;
  }

  bool _containsKeyword(String text, String keyword) {
    final normalizedKeyword = keyword.toLowerCase();
    // Short Cyrillic abbreviations such as «ИИ» must match as whole words;
    // substring matching would incorrectly classify «России» as AI news.
    if (normalizedKeyword == 'ии') {
      return RegExp(
        r'''(^|[\s.,!?()\[\]{}:;"'«»—-])ии([\s.,!?()\[\]{}:;"'«»—-]|$)''',
        caseSensitive: false,
      ).hasMatch(text);
    }
    return text.contains(normalizedKeyword);
  }

  DateTime? _parseDate(String value) {
    final input = value.trim();
    if (input.isEmpty) return null;
    try {
      return HttpDate.parse(input).toUtc();
    } on HttpException {
      // RSS feeds may contain arbitrary date strings. Treat malformed dates as
      // missing publication metadata so the item is skipped safely.
      return DateTime.tryParse(input)?.toUtc();
    } on FormatException {
      return DateTime.tryParse(input)?.toUtc();
    }
  }

  String _tag(String xml, String name, {bool decodeEntities = true}) {
    final escapedName = RegExp.escape(name);
    final match = RegExp(
      '<$escapedName(?:\\s[^>]*)?>([\\s\\S]*?)</$escapedName>',
      caseSensitive: false,
    ).firstMatch(xml);
    if (match == null) return '';
    var value = match.group(1) ?? '';
    value = value.replaceAllMapped(
      RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>'),
      (match) => match.group(1) ?? '',
    );
    return (decodeEntities ? _decodeEntities(value) : value).trim();
  }

  String _stripMarkup(String value) {
    final decoded = _decodeEntities(
      value.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' '),
    );
    // Encoded angle brackets are text, not markup. Remove the brackets while
    // retaining their contents so excerpts remain readable and predictable.
    return decoded.replaceAll('<', '').replaceAll('>', '').trim();
  }

  String _decodeEntities(String value) {
    final namedDecoded = value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#8217;', '’')
        .replaceAll('&#8211;', '–')
        .replaceAll('&#160;', ' ');

    // RSS publishers commonly encode punctuation and symbols as decimal or
    // hexadecimal numeric references. Decode valid Unicode scalar values only.
    return namedDecoded.replaceAllMapped(
      RegExp(r'&#(x[0-9a-f]+|[0-9]+);', caseSensitive: false),
      (match) {
        final token = match.group(1)!;
        final codePoint = token.toLowerCase().startsWith('x')
            ? int.tryParse(token.substring(1), radix: 16)
            : int.tryParse(token);
        if (codePoint == null ||
            codePoint <= 0 ||
            codePoint > 0x10ffff ||
            (codePoint >= 0xd800 && codePoint <= 0xdfff)) {
          return match.group(0)!;
        }
        return String.fromCharCode(codePoint);
      },
    );
  }

  static String _failureSummary(Object error) {
    if (error is NewsRssException) {
      final code = error.statusCode == null ? '' : ' HTTP ${error.statusCode}';
      return 'ClientException/${error.kind.name}$code';
    }
    if (error is TimeoutException) return 'TimeoutException/timeout';
    if (error is SocketException) return 'SocketException/network';
    return error.runtimeType.toString();
  }

  void dispose() => _client.close();
}
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/core/ai_engine/local/local_model_storage.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/providers/routing_ai_provider.dart';
import 'package:omni_ai/core/di/ai_dependencies.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class LocalModelSettingsPage extends StatefulWidget {
  const LocalModelSettingsPage({
    required this.storage,
    this.aiDependencies,
    super.key,
  });

  final LocalModelStorage storage;
  final AIDependencies? aiDependencies;

  @override
  State<LocalModelSettingsPage> createState() => _LocalModelSettingsPageState();
}

class _LocalModelSettingsPageState extends State<LocalModelSettingsPage> {
  static const _model = LocalModelCatalog.qwen3Small;

  bool _checking = true;
  bool _installing = false;
  bool _installed = false;
  String? _error;
  String? _status;
  AIExecutionMode _executionMode = AIExecutionMode.local;
  bool _modeLoading = false;
  bool _modeSaving = false;
  String? _modeError;
  final TextEditingController _cloudKeyController = TextEditingController();
  bool _hasCloudKey = false;
  bool _keyLoading = false;
  bool _keySaving = false;
  bool _cloudTesting = false;
  String? _keyMessage;

  @override
  void dispose() {
    _cloudKeyController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    if (widget.aiDependencies != null) {
      _modeLoading = true;
      _keyLoading = true;
      unawaited(_restoreExecutionMode());
      unawaited(_restoreCloudKeyStatus());
    }
  }

  Future<void> _restoreExecutionMode() async {
    try {
      await widget.aiDependencies!.restoreExecutionMode();
      if (!mounted) return;
      setState(() => _executionMode = widget.aiDependencies!.executionMode);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _modeError = 'Не удалось восстановить режим AI: $error');
    } finally {
      if (mounted) setState(() => _modeLoading = false);
    }
  }

  Future<void> _restoreCloudKeyStatus() async {
    try {
      final hasKey = await widget.aiDependencies!.hasCloudApiKey;
      if (!mounted) return;
      setState(() => _hasCloudKey = hasKey);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _keyMessage = 'Не удалось проверить ключ: $error');
    } finally {
      if (mounted) setState(() => _keyLoading = false);
    }
  }

  Future<void> _saveCloudKey() async {
    final dependencies = widget.aiDependencies;
    final key = _cloudKeyController.text.trim();
    if (dependencies == null || key.isEmpty || _keySaving) return;
    setState(() {
      _keySaving = true;
      _keyMessage = null;
    });
    try {
      await dependencies.saveCloudApiKey(key);
      if (!mounted) return;
      _cloudKeyController.clear();
      setState(() {
        _hasCloudKey = true;
        _keyMessage = 'Ключ сохранён в защищённом хранилище устройства.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _keyMessage = 'Не удалось сохранить ключ: $error');
    } finally {
      if (mounted) setState(() => _keySaving = false);
    }
  }

  Future<void> _testCloudConnection() async {
    final dependencies = widget.aiDependencies;
    if (dependencies == null || _cloudTesting) return;
    setState(() {
      _cloudTesting = true;
      _keyMessage = 'Проверяем реальный ответ OpenRouter…';
    });
    try {
      final response = await dependencies.cloudProvider
          .complete(
            const AIRequest(
              id: 'openrouter-connection-check',
              prompt: 'Ответь одним словом: OK',
            ),
            cancellationToken: AICancellationToken(),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(
        () => _keyMessage =
            'Облако отвечает (${response.providerId}, '
            '${response.metadata['model'] ?? 'модель не указана'}).',
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _keyMessage = 'Проверка облака не прошла: $error');
    } finally {
      if (mounted) setState(() => _cloudTesting = false);
    }
  }

  Future<void> _deleteCloudKey() async {
    final dependencies = widget.aiDependencies;
    if (dependencies == null || _keySaving) return;
    setState(() {
      _keySaving = true;
      _keyMessage = null;
    });
    try {
      await dependencies.deleteCloudApiKey();
      if (!mounted) return;
      setState(() {
        _hasCloudKey = false;
        _keyMessage = 'Облачный ключ удалён с устройства.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _keyMessage = 'Не удалось удалить ключ: $error');
    } finally {
      if (mounted) setState(() => _keySaving = false);
    }
  }

  Future<void> _selectExecutionMode(AIExecutionMode mode) async {
    final dependencies = widget.aiDependencies;
    if (dependencies == null || _modeLoading || _modeSaving) return;
    final previousMode = _executionMode;
    setState(() {
      _executionMode = mode;
      _modeSaving = true;
      _modeError = null;
    });
    try {
      await dependencies.setExecutionMode(mode);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _executionMode = previousMode;
          _modeError = 'Не удалось сохранить режим AI: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _modeSaving = false);
    }
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final installed = await widget.storage.isDownloaded(_model);
      if (!mounted) return;
      setState(() {
        _installed = installed;
        _checking = false;
        _status = installed ? 'Модель уже находится на устройстве.' : null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Не удалось проверить файлы модели: $error';
      });
    }
  }

  Future<void> _download() async {
    if (_installing) return;
    setState(() {
      _installing = true;
      _error = null;
      _status = _installed
          ? 'Проверяем целостность установленной модели…'
          : 'Скачиваем модель. Нужны стабильный интернет и около 500 МБ свободного места.';
    });
    try {
      if (_installed && await widget.storage.isValid(_model)) {
        if (!mounted) return;
        setState(
          () => _status = 'Модель уже установлена и прошла проверку SHA-256.',
        );
        return;
      }
      await widget.storage.download(_model);
      if (!mounted) return;
      setState(() {
        _installed = true;
        _status = 'Модель скачана и проверена по размеру и SHA-256.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось скачать или проверить модель: $error';
        _status = null;
      });
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _delete() async {
    if (_installing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить локальную модель?'),
        content: const Text(
          'Файл модели будет удалён из хранилища приложения. '
          'Для повторной установки потребуется скачать около 500 МБ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ОТМЕНА'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('УДАЛИТЬ'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.storage.delete(_model);
      if (!mounted) return;
      setState(() {
        _installed = false;
        _status = 'Файл модели удалён.';
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось удалить модель: $error');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} КБ';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('local-model-settings-page'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        const Text(
          '05 // ON-DEVICE INFERENCE',
          style: TextStyle(
            color: SystemCorePalette.muted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'ЛОКАЛЬНАЯ МОДЕЛЬ',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Модель скачивается отдельно один раз и хранится в закрытой папке приложения. '
          'Обычные обновления приложения её не содержат и не удаляют.',
          style: TextStyle(color: SystemCorePalette.muted, fontSize: 12),
        ),
        if (widget.aiDependencies != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SystemCorePalette.panel,
              border: Border.all(
                color: SystemCorePalette.border.withValues(alpha: 0.55),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'РЕЖИМ ВЫПОЛНЕНИЯ AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<AIExecutionMode>(
                  segments: const [
                    ButtonSegment(
                      value: AIExecutionMode.automatic,
                      icon: Icon(Icons.auto_awesome),
                      label: Text('Авто'),
                    ),
                    ButtonSegment(
                      value: AIExecutionMode.local,
                      icon: Icon(Icons.phone_android),
                      label: Text('Local AI'),
                    ),
                    ButtonSegment(
                      value: AIExecutionMode.cloud,
                      icon: Icon(Icons.cloud_outlined),
                      label: Text('Cloud AI'),
                    ),
                  ],
                  selected: {_executionMode},
                  onSelectionChanged: _modeLoading || _modeSaving
                      ? null
                      : (selection) =>
                            unawaited(_selectExecutionMode(selection.first)),
                ),
                const SizedBox(height: 10),
                Text(
                  switch (_executionMode) {
                    AIExecutionMode.automatic =>
                      'Авто: команды приложения обрабатываются локально, рекомендации и сложные вопросы направляются в облако. При сбое облака выполняется попытка локального ответа.',
                    AIExecutionMode.local =>
                      'Локальный режим: запросы не отправляются облачному провайдеру. Сначала установите встроенную модель ниже.',
                    AIExecutionMode.cloud =>
                      'Облачный режим: используется OpenRouter (openrouter/free). Нужен API-ключ; он не должен вшиваться в APK.',
                  },
                  style: const TextStyle(
                    color: SystemCorePalette.muted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'ОБЛАЧНЫЙ ДОСТУП // OPENROUTER',
                  style: TextStyle(
                    color: SystemCorePalette.green,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('openrouter-api-key-field'),
                  controller: _cloudKeyController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Личный API-ключ OpenRouter',
                    hintText: 'sk-or-…',
                    helperText:
                        'Создаётся в аккаунте OpenRouter. Не отправляйте ключ в чат.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('save-openrouter-key-button'),
                        onPressed: _keyLoading || _keySaving
                            ? null
                            : _saveCloudKey,
                        icon: _keySaving
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.lock_outline),
                        label: const Text('СОХРАНИТЬ КЛЮЧ'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      key: const ValueKey('delete-openrouter-key-button'),
                      tooltip: 'Удалить ключ',
                      onPressed: !_hasCloudKey || _keySaving
                          ? null
                          : _deleteCloudKey,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const ValueKey('test-openrouter-connection-button'),
                    onPressed: !_hasCloudKey || _cloudTesting || _keyLoading
                        ? null
                        : _testCloudConnection,
                    icon: _cloudTesting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_done_outlined),
                    label: Text(
                      _cloudTesting
                          ? 'ПРОВЕРКА ОБЛАКА…'
                          : 'ПРОВЕРИТЬ ОБЛАЧНЫЙ ИИ',
                    ),
                  ),
                ),
                Text(
                  _keyLoading
                      ? 'Проверяем сохранённый ключ…'
                      : _hasCloudKey
                      ? 'Ключ настроен на этом устройстве.'
                      : 'Ключ не настроен.',
                  style: const TextStyle(
                    color: SystemCorePalette.muted,
                    fontSize: 11,
                  ),
                ),
                if (_keyMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _keyMessage!,
                    style: const TextStyle(
                      color: SystemCorePalette.green,
                      fontSize: 11,
                    ),
                  ),
                ],
                if (_modeLoading || _modeSaving) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(color: SystemCorePalette.green),
                ],
                if (_modeError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _modeError!,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SystemCorePalette.panel,
            border: Border.all(
              color: SystemCorePalette.border.withValues(alpha: 0.55),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.memory,
                color: SystemCorePalette.green,
                size: 28,
              ),
              const SizedBox(height: 12),
              Text(
                _model.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ориентировочный размер: '
                '${_formatBytes(_model.expectedBytesApprox)}',
                style: const TextStyle(
                  color: SystemCorePalette.muted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Формат GGUF · Q4_K_M · отдельная загрузка · после установки работает офлайн',
                style: TextStyle(color: SystemCorePalette.muted, fontSize: 11),
              ),
              const SizedBox(height: 16),
              if (_checking)
                const LinearProgressIndicator(color: SystemCorePalette.green)
              else
                Row(
                  children: [
                    Icon(
                      _installed ? Icons.check_circle : Icons.info_outline,
                      color: _installed
                          ? SystemCorePalette.green
                          : SystemCorePalette.muted,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _installed
                            ? 'Файл модели найден'
                            : 'Модель не установлена',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              if (_status != null) ...[
                const SizedBox(height: 12),
                Text(
                  _status!,
                  style: const TextStyle(
                    color: SystemCorePalette.green,
                    fontSize: 11,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 11,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('local-model-download-button'),
                  onPressed: _checking || _installing ? null : _download,
                  icon: _installing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(
                    _installing
                        ? 'ЗАГРУЗКА / ПРОВЕРКА…'
                        : _installed
                        ? 'ПОВТОРНО ПРОВЕРИТЬ МОДЕЛЬ'
                        : 'СКАЧАТЬ ЛОКАЛЬНУЮ МОДЕЛЬ',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('local-model-delete-button'),
                  onPressed: _checking || _installing || !_installed
                      ? null
                      : _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('УДАЛИТЬ ФАЙЛ'),
                ),
              ),
              if (!_installing && !_checking) ...[
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: _refreshStatus,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('ПРОВЕРИТЬ СНОВА'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Загружаемый файл проверяется по ожидаемому размеру и SHA-256. '
          'После первой загрузки интернет для локального ИИ не требуется.',
          style: TextStyle(color: SystemCorePalette.muted, fontSize: 11),
        ),
      ],
    );
  }
}
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/local/local_model_storage.dart';
import 'package:omni_ai/core/ai_engine/local/stored_local_llama_provider.dart';
import 'package:omni_ai/core/ai_engine/models/ai_error.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';

void main() {
  test('reports a missing model without attempting a download', () async {
    final directory = await Directory.systemTemp.createTemp('omni-local-ai-');
    final storage = LocalModelStorage(
      supportDirectoryProvider: () async => directory,
    );
    final provider = StoredLocalLlamaProvider(
      storage: storage,
      autoInstallBundledModel: false,
      model: const LocalModelSpec(
        id: 'test-model',
        displayName: 'Test model',
        fileName: 'test.gguf',
        downloadUri: 'https://example.invalid/test.gguf',
        expectedBytesApprox: 10,
      ),
    );

    addTearDown(() async {
      await provider.dispose();
      storage.dispose();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    await expectLater(
      provider.complete(
        AIRequest(id: 'missing-model', prompt: 'Hello'),
        cancellationToken: AICancellationToken(),
      ),
      throwsA(
        isA<AIEngineException>().having(
          (error) => error.error.message,
          'message',
          contains('Локальная модель не установлена'),
        ),
      ),
    );

    expect(await directory.list().toList(), isEmpty);
  });
}
