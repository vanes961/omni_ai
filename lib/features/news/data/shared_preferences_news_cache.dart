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

  final NewsCacheStringStore _store;

  Future<List<NewsArticle>> loadArticles() async {
    final encoded = await _store.read(articlesKey);
    if (encoded == null || encoded.isEmpty) return const <NewsArticle>[];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) throw const FormatException('Expected a list.');
      final articles = <NewsArticle>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final article = _articleFromJson(item);
        if (article != null) articles.add(article);
      }
      return articles;
    } on FormatException {
      await _store.remove(articlesKey);
      return const <NewsArticle>[];
    }
  }

  Future<void> saveArticles(List<NewsArticle> articles) async {
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
        })
        .toList(growable: false);
    await _store.write(articlesKey, jsonEncode(encoded));
  }

  Future<String?> loadDigest() async {
    final digest = await _store.read(digestKey);
    if (digest == null || digest.trim().isEmpty) return null;
    return digest;
  }

  Future<void> saveDigest(String? digest) async {
    if (digest == null || digest.trim().isEmpty) {
      await _store.remove(digestKey);
    } else {
      await _store.write(digestKey, digest.trim());
    }
  }

  NewsArticle? _articleFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final summary = json['summary'];
    final sourceName = json['sourceName'];
    final sourceUrl = json['sourceUrl'];
    final publishedAt = DateTime.tryParse(json['publishedAt'] as String? ?? '');
    final uri = Uri.tryParse(sourceUrl as String? ?? '');
    if (id is! String ||
        title is! String ||
        summary is! String ||
        sourceName is! String ||
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
