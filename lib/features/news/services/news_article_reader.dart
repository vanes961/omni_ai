import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/news_article.dart';

/// Loads readable publisher text and social-preview images for an RSS item.
/// RSS remains the discovery source; this reader enriches a single opened item.
class NewsArticleReader {
  NewsArticleReader({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  static const _requestTimeout = Duration(seconds: 12);
  static const _maxHtmlBytes = 2 * 1024 * 1024;
  static const _maxArticleCharacters = 24000;

  Future<NewsArticle> read(NewsArticle article) async {
    if (article.content.isNotEmpty && article.thumbnailUrl != null) {
      return article;
    }
    final uri = Uri.tryParse(article.sourceUrl);
    if (uri == null || !_isSafeHttpsUri(uri)) return article;

    try {
      final response = await _client
          .get(
            uri,
            headers: const {
              'User-Agent': 'OMNI-AI-News/1.0',
              'Accept': 'text/html,application/xhtml+xml',
            },
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200 ||
          response.bodyBytes.length > _maxHtmlBytes) {
        return article;
      }
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.isNotEmpty &&
          !contentType.contains('text/html') &&
          !contentType.contains('application/xhtml+xml')) {
        return article;
      }

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final document = html_parser.parse(html);
      final image = _findImage(document, uri) ?? article.thumbnailUrl;
      final root = document.querySelector('article') ??
          document.querySelector('main') ??
          document.querySelector('[role="main"]') ??
          document.body;
      if (root == null) return _withArticleData(article, content: '', image: image);

      for (final element in root.querySelectorAll(
        'script,style,noscript,nav,footer,header,aside,form,iframe,svg,button',
      )) {
        element.remove();
      }

      final paragraphs = root
          .querySelectorAll('h1,h2,h3,p,blockquote,li')
          .map((element) => _cleanText(element.text))
          .where((text) => text.length >= 28)
          .toList(growable: false);
      final extracted = paragraphs.isNotEmpty
          ? paragraphs.join('\n\n')
          : _cleanText(root.text);
      final content = extracted.length > _maxArticleCharacters
          ? extracted.substring(0, _maxArticleCharacters).trimRight()
          : extracted;
      return _withArticleData(
        article,
        content: content.length >= 120 ? content : '',
        image: image,
      );
    } on Object {
      // A publisher may block automated readers. Keep the RSS card usable.
      return article;
    }
  }

  String? _findImage(dynamic document, Uri baseUri) {
    final candidates = <String?>[
      document.querySelector('meta[property="og:image"]')?.attributes['content'],
      document.querySelector('meta[name="twitter:image"]')?.attributes['content'],
      document.querySelector('link[rel="image_src"]')?.attributes['href'],
    ];
    for (final candidate in candidates) {
      if (candidate == null || candidate.trim().isEmpty) continue;
      final resolved = baseUri.resolve(candidate.trim());
      if (_isSafeHttpsUri(resolved)) return resolved.toString();
    }
    return null;
  }

  bool _isSafeHttpsUri(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal')) {
      return false;
    }
    final ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$')
        .firstMatch(host);
    if (ipv4 != null) {
      final octets = List<int>.generate(
        4,
        (index) => int.parse(ipv4.group(index + 1)!),
      );
      final first = octets[0];
      final second = octets[1];
      if (octets.any((value) => value > 255) ||
          first == 0 ||
          first == 10 ||
          first == 127 ||
          (first == 169 && second == 254) ||
          (first == 172 && second >= 16 && second <= 31) ||
          (first == 192 && second == 168)) {
        return false;
      }
    }
    return true;
  }

  String _cleanText(String value) => value
      .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  NewsArticle _withArticleData(
    NewsArticle article, {
    required String content,
    required String? image,
  }) {
    return NewsArticle(
      id: article.id,
      title: article.title,
      summary: article.summary,
      sourceName: article.sourceName,
      sourceUrl: article.sourceUrl,
      publishedAt: article.publishedAt,
      topics: article.topics,
      language: article.language,
      region: article.region,
      isCritical: article.isCritical,
      isVerified: article.isVerified,
      contentType: article.contentType,
      videoUrl: article.videoUrl,
      thumbnailUrl: image,
      content: content,
      channelName: article.channelName,
      releaseDate: article.releaseDate,
      releaseDateSourceUrl: article.releaseDateSourceUrl,
    );
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}
