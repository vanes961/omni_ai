import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:omni_ai/features/news/models/news_article.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';
import 'package:omni_ai/features/news/services/news_relevance_filter.dart';

/// Reads public Google News RSS search results. No API key is embedded in the
/// application. RSS excerpts are displayed with source attribution; full
/// publisher articles remain at their original source.
class NewsRssService {
  NewsRssService({http.Client? client, NewsRelevanceFilter? filter})
    : _client = client ?? http.Client(),
      _filter = filter ?? const NewsRelevanceFilter();

  final http.Client _client;
  final NewsRelevanceFilter _filter;

  static const _topicKeywords = <String, List<String>>{
    'games': ['game', 'gaming', 'video game', 'игр', 'гейминг'],
    'anime': ['anime', 'аниме'],
    'manga': ['manga', 'манга'],
    'movies': ['movie', 'movies', 'cinema', 'film', 'кино', 'фильм'],
    'series': ['series', 'tv series', 'streaming', 'сериал', 'сериалы'],
    'technology': ['technology', 'tech', 'технолог', 'техника'],
    'artificial intelligence': ['artificial intelligence', ' ai ', 'ии', 'искусственн', 'нейросет'],
    'science': ['science', 'scientific', 'наук', 'исследован'],
    'space': ['space', 'astronomy', 'spaceflight', 'космос', 'астроном', 'космич'],
    'gadgets': ['gadget', 'electronics', 'smartphone', 'гаджет', 'смартфон', 'электроник'],
  };

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


  /// Collects candidates from Russian and English Google News editions.
  /// Edition locale describes the feed, not the article's actual geography.
  Future<List<NewsArticle>> fetchInternational(
    NewsInterestProfile profile,
  ) async {
    if (profile.topics.isEmpty) return const <NewsArticle>[];

    const locales = <List<String>>[
      ['ru', 'RU'],
      ['en', 'US'],
      ['en', 'GB'],
    ];
    var successfulEditions = 0;
    final batches = await Future.wait(
      locales.map((locale) async {
        try {
          final articles = await fetch(
            profile.copyWith(
              languages: <String>[locale[0]],
              regions: <String>[locale[1]],
            ),
            applyRelevanceFilter: false,
          );
          successfulEditions++;
          return articles;
        } catch (_) {
          // One unavailable edition should not block the remaining sources.
          return const <NewsArticle>[];
        }
      }),
    );
    if (successfulEditions == 0) {
      throw http.ClientException(
        'All international news editions are unavailable.',
      );
    }

    final byUrl = <String, NewsArticle>{};
    for (final article in batches.expand((batch) => batch)) {
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

    final unrestrictedProfile = profile.copyWith(
      topics: profile.topics.map(_canonicalTopic).toSet().toList(growable: false),
      languages: const <String>[],
      regions: const <String>[],
    );
    return _filter.filter(byTitle.values, unrestrictedProfile);
  }

  Future<List<NewsArticle>> fetch(
    NewsInterestProfile profile, {
    bool applyRelevanceFilter = true,
  }) async {
    if (profile.topics.isEmpty) return const <NewsArticle>[];
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
    final query = canonicalTopics
        .map((topic) => _topicQueries[topic] ?? topic)
        .join(' OR ');
    final canonicalProfile = profile.copyWith(topics: canonicalTopics);
    if (query.isEmpty) return const <NewsArticle>[];
    final uri = Uri.https('news.google.com', '/rss/search', {
      'q': query,
      'hl': language == 'ru' ? 'ru' : language,
      'gl': region,
      'ceid': '$region:$language',
    });
    final response = await _client
        .get(uri, headers: const {'User-Agent': 'OMNI-AI-News/1.0'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'News source returned HTTP ${response.statusCode}.',
        uri,
      );
    }

    final xml = utf8.decode(response.bodyBytes, allowMalformed: true);
    final articles = _parseItems(
      xml,
      language,
      region.toLowerCase(),
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
    final kept = uri.queryParametersAll.entries
        .where((entry) {
          final key = entry.key.toLowerCase();
          return !key.startsWith('utm_') && !trackingKeys.contains(key);
        })
        .toList()
      ..sort((a, b) {
        final byKey = a.key.toLowerCase().compareTo(b.key.toLowerCase());
        return byKey != 0
            ? byKey
            : a.value.join(',').compareTo(b.value.join(','));
      });
    final query = <String, dynamic>{
      for (final entry in kept) entry.key: entry.value,
    };
    return uri.replace(
      fragment: '',
      query: query.isEmpty ? '' : null,
      queryParameters: query.isEmpty ? null : query,
      path: uri.path.isEmpty ? '/' : uri.path,
    ).toString();
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

  List<NewsArticle> _parseItems(String xml, String language, String? profileRegion) {
    final items = RegExp(r'<item(?:\s[^>]*)?>([\s\S]*?)</item>',
      caseSensitive: false).allMatches(xml);
    final result = <NewsArticle>[];
    for (final match in items) {
      final item = match.group(1) ?? '';
      final title = _tag(item, 'title');
      final link = _tag(item, 'link');
      final description = _tag(item, 'description', decodeEntities: false);
      final published = _parseDate(_tag(item, 'pubDate')) ??
          _parseDate(_tag(item, 'dc:date'));
      if (title.isEmpty || link.isEmpty || published == null) continue;
      final uri = Uri.tryParse(link);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
      final sourceName = _tag(item, 'source').isNotEmpty
          ? _tag(item, 'source')
          : uri.host;
      final text = _stripMarkup(description);
      final normalized = ' ${title.toLowerCase()} ${text.toLowerCase()} ';
      final topics = _topicKeywords.entries
          .where((entry) => entry.value.any(
                (keyword) => _containsKeyword(normalized, keyword),
              ))
          .map((entry) => entry.key)
          .toList(growable: false);
      result.add(NewsArticle(
        id: uri.toString(),
        title: title,
        summary: text,
        sourceName: sourceName,
        sourceUrl: uri.toString(),
        publishedAt: published.toUtc(),
        topics: topics,
        language: language,
        region: profileRegion,
        isVerified: true,
      ));
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
      value
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' '),
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

  void dispose() => _client.close();
}
