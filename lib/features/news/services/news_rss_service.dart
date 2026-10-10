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

  Future<List<NewsArticle>> fetch(NewsInterestProfile profile) async {
    if (profile.topics.isEmpty) return const <NewsArticle>[];
    final language = profile.languages.isNotEmpty ? profile.languages.first : 'ru';
    final query = profile.topics
        .map((topic) => _topicQueries[topic.toLowerCase()] ?? topic)
        .join(' OR ');
    final uri = Uri.https('news.google.com', '/rss/search', {
      'q': query,
      'hl': language == 'ru' ? 'ru' : language,
      'gl': profile.regions.isNotEmpty ? profile.regions.first.toUpperCase() : 'RU',
      'ceid': '${profile.regions.isNotEmpty ? profile.regions.first.toUpperCase() : 'RU'}:$language',
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
      profile.regions.isNotEmpty ? profile.regions.first : null,
    );
    final unique = <String, NewsArticle>{};
    for (final article in articles) {
      final key = article.sourceUrl.trim();
      if (key.isNotEmpty) unique.putIfAbsent(key, () => article);
    }
    return _filter.filter(unique.values, profile);
  }

  List<NewsArticle> _parseItems(String xml, String language, String? profileRegion) {
    final items = RegExp(r'<item(?:\s[^>]*)?>([\s\S]*?)</item>',
      caseSensitive: false).allMatches(xml);
    final result = <NewsArticle>[];
    for (final match in items) {
      final item = match.group(1) ?? '';
      final title = _tag(item, 'title');
      final link = _tag(item, 'link');
      final description = _tag(item, 'description');
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

  String _tag(String xml, String name) {
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
    return _decodeEntities(value).trim();
  }

  String _stripMarkup(String value) => _decodeEntities(
    value.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' '),
  ).trim();

  String _decodeEntities(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#8217;', '’')
      .replaceAll('&#8211;', '–')
      .replaceAll('&#160;', ' ');

  void dispose() => _client.close();
}
