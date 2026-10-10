import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_ai/features/news/models/news_article.dart';

abstract interface class NewsCacheStringStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// Stores the last personalized feed and digest on this device for offline
/// viewing. This cache contains only articles the feed service already filtered.
class SharedPreferencesNewsCache {
  SharedPreferencesNewsCache({NewsCacheStringStore? store})
    : _store = store ?? _SharedPreferencesNewsCacheStringStore();

  static const articlesKey = 'omni_ai.news_cache.articles.v1';
  static const digestKey = 'omni_ai.news_cache.digest.v1';
  static const topicsKey = 'omni_ai.news_cache.topics.v1';

  final NewsCacheStringStore _store;

  Future<List<NewsArticle>> loadArticles() async {
    final encoded = await _store.read(articlesKey);
    if (encoded == null || encoded.isEmpty) return const <NewsArticle>[];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) throw const FormatException('Expected a list.');
      final articles = <NewsArticle>[];
      final seenIds = <String>{};
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final article = _articleFromJson(item);
        // A corrupt or duplicated cache entry must not create repeated cards
        // (or repeated widget keys) when the feed is restored after restart.
        if (article != null && seenIds.add(article.id)) {
          articles.add(article);
        }
      }
      return articles;
    } on FormatException {
      await _store.remove(articlesKey);
      return const <NewsArticle>[];
    }
  }

  Future<List<String>?> loadTopics() async {
    final encoded = await _store.read(topicsKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List || decoded.any((item) => item is! String)) {
        throw const FormatException('Expected a list of topic strings.');
      }
      return decoded.cast<String>();
    } on FormatException {
      await _store.remove(topicsKey);
      return null;
    }
  }

  Future<void> saveArticles(
    List<NewsArticle> articles, {
    List<String> selectedTopics = const <String>[],
  }) async {
    final encoded = articles
        .map((article) => <String, Object?>{
          'id': article.id,
          'title': article.title,
          'summary': article.summary,
          'sourceName': article.sourceName,
          'sourceUrl': article.sourceUrl,
          'publishedAt': article.publishedAt.toIso8601String(),
          'topics': article.topics,
          'language': article.language,
          'region': article.region,
          'isCritical': article.isCritical,
          'isVerified': article.isVerified,
          'contentType': article.contentType.name,
          'videoUrl': article.videoUrl,
          'thumbnailUrl': article.thumbnailUrl,
          'channelName': article.channelName,
          'releaseDate': article.releaseDate?.toIso8601String(),
          'releaseDateSourceUrl': article.releaseDateSourceUrl,
        })
        .toList(growable: false);
    // A digest describes one particular feed. Invalidate it before replacing
    // the articles so it cannot be restored beside a different or empty feed.
    await _store.remove(digestKey);
    // Remove the previous payload before changing its topic marker. Otherwise,
    // if the new article write fails, the new marker could incorrectly make the
    // previous feed look valid on the next launch.
    await _store.remove(articlesKey);
    await _store.write(topicsKey, jsonEncode(_normalizeTopics(selectedTopics)));
    await _store.write(articlesKey, jsonEncode(encoded));
  }

  Future<String?> loadDigest() async {
    final digest = await _store.read(digestKey);
    if (digest == null || digest.trim().isEmpty) return null;
    return digest;
  }

  Future<void> clear() async {
    await _store.remove(articlesKey);
    await _store.remove(digestKey);
    await _store.remove(topicsKey);
  }

  List<String> _normalizeTopics(List<String> topics) => topics
      .map((topic) => topic.trim().toLowerCase())
      .where((topic) => topic.isNotEmpty)
      .toSet()
      .toList()..sort();

  Future<void> saveDigest(String? digest) async {
    if (digest == null || digest.trim().isEmpty) {
      await _store.remove(digestKey);
    } else {
      await _store.write(digestKey, digest.trim());
    }
  }

  String? _safeHttpsUrl(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri.toString();
  }

  NewsArticle? _articleFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final summary = json['summary'];
    final sourceName = json['sourceName'];
    final sourceUrl = json['sourceUrl'];
    final publishedRaw = json['publishedAt'];
    final publishedAt = publishedRaw is String
        ? DateTime.tryParse(publishedRaw)
        : null;
    final uri = Uri.tryParse(sourceUrl is String ? sourceUrl : '');
    if (id is! String ||
        id.trim().isEmpty ||
        title is! String ||
        title.trim().isEmpty ||
        summary is! String ||
        sourceName is! String ||
        sourceName.trim().isEmpty ||
        sourceUrl is! String ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        publishedAt == null) {
      return null;
    }
    final rawTopics = json['topics'];
    final topics = rawTopics is List
        ? rawTopics.whereType<String>().toList(growable: false)
        : const <String>[];
    final videoUrl = _safeHttpsUrl(json['videoUrl']);
    final thumbnailUrl = _safeHttpsUrl(json['thumbnailUrl']);
    final releaseDateSourceUrl = _safeHttpsUrl(json['releaseDateSourceUrl']);
    final releaseDateRaw = json['releaseDate'];
    final parsedReleaseDate = releaseDateRaw is String
        ? DateTime.tryParse(releaseDateRaw)
        : null;

    return NewsArticle(
      id: id,
      title: title,
      summary: summary,
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      publishedAt: publishedAt,
      topics: topics,
      language: json['language'] is String ? json['language'] as String : 'ru',
      region: json['region'] is String ? json['region'] as String : null,
      isCritical: json['isCritical'] == true,
      isVerified: json['isVerified'] == true,
      contentType: NewsContentType.fromJson(json['contentType']),
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
      channelName: json['channelName'] is String
          ? (json['channelName'] as String).trim()
          : null,
      releaseDate: parsedReleaseDate != null && releaseDateSourceUrl != null
          ? parsedReleaseDate
          : null,
      releaseDateSourceUrl: releaseDateSourceUrl,
    );
  }
}

class _SharedPreferencesNewsCacheStringStore implements NewsCacheStringStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<void> remove(String key) => _preferences.remove(key);
}
