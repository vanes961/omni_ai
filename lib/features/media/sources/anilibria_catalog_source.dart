import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/sources/media_source.dart';

/// Russian-language anime catalog adapter for the documented AniLibria API.
///
/// This adapter returns catalog metadata only. It does not scrape HTML, bypass
/// access restrictions, or treat stream URLs as metadata. Playback integration
/// must be handled separately and only for streams the source explicitly
/// provides for use by its player.
class AniLibriaCatalogSource implements MediaSource {
  AniLibriaCatalogSource({
    this.client,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 10),
  }) : baseUri =
           baseUri ??
           Uri.https('api.anilibria.app', '/api/v1/app/search/releases');

  final http.Client? client;
  final Uri baseUri;
  final Duration timeout;

  @override
  String get id => 'anilibria';

  @override
  Set<MediaSourceKind> get supportedKinds => const {MediaSourceKind.anime};

  Future<http.Response> _get(Uri uri) {
    final transport = client;
    return (transport == null ? http.get(uri) : transport.get(uri)).timeout(
      timeout,
    );
  }

  @override
  Future<List<MediaItem>> search(
    String query, {
    required MediaSourceKind kind,
  }) async {
    if (!supportedKinds.contains(kind) || query.trim().isEmpty) {
      return const <MediaItem>[];
    }

    final uri = baseUri.replace(
      queryParameters: {...baseUri.queryParameters, 'query': query.trim()},
    );
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw HttpException('AniLibria returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final entries = _extractEntries(decoded);
    final results = <MediaItem>[];
    for (final raw in entries) {
      final item = _toMediaItem(raw);
      if (item != null) results.add(item);
    }
    return List<MediaItem>.unmodifiable(results);
  }

  List<Map<String, dynamic>> _extractEntries(Object? decoded) {
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    if (decoded is! Map<String, dynamic>) return const [];
    final list =
        decoded['list'] ??
        decoded['data'] ??
        decoded['items'] ??
        decoded['results'] ??
        decoded['releases'];
    if (list is List) {
      return list.whereType<Map<String, dynamic>>().toList();
    }
    // Some API responses may return a single title object.
    if (decoded.containsKey('id') &&
        (decoded.containsKey('names') || decoded.containsKey('name'))) {
      return [decoded];
    }
    return const [];
  }

  MediaItem? _toMediaItem(Map<String, dynamic> raw) {
    final id = raw['id'];
    final names = raw['names'];
    final modernName = raw['name'];
    final title = names is Map<String, dynamic>
        ? ((names['ru'] as String?) ?? (names['en'] as String?) ?? '')
        : modernName is Map<String, dynamic>
        ? ((modernName['main'] as String?) ??
              (modernName['english'] as String?) ??
              (modernName['alternative'] as String?) ??
              '')
        : (modernName as String? ?? '');
    if (id == null || title.trim().isEmpty) return null;

    final poster = raw['posters'] ?? raw['poster'];
    final posterObject = poster is Map<String, dynamic>
        ? (poster['medium'] ??
              poster['preview'] ??
              poster['thumbnail'] ??
              poster['optimized'] ??
              poster['small'] ??
              poster['original'])
        : null;
    final posterUrl = posterObject is Map<String, dynamic>
        ? (posterObject['url'] as String? ??
              posterObject['src'] as String? ??
              '')
        : posterObject is String
        ? posterObject
        : '';

    final genrePayload = raw['genres'];
    final genres = genrePayload is List
        ? genrePayload
              .map((value) {
                if (value is String) return value;
                if (value is Map<String, dynamic>) {
                  return value['name'] as String? ?? value['title'] as String?;
                }
                return null;
              })
              .whereType<String>()
              .where((value) => value.trim().isNotEmpty)
              .toList()
        : const <String>[];

    final description = _plainText(
      raw['description'] as String? ?? raw['announce'] as String? ?? '',
    );
    final ratingPayload = raw['rating'];
    final rating = ratingPayload is num
        ? ratingPayload.toDouble()
        : ratingPayload is Map<String, dynamic>
        ? ((ratingPayload['average'] ?? ratingPayload['value']) as num?)
                  ?.toDouble() ??
              0.0
        : 0.0;
    final yearPayload = raw['season'];
    final year = yearPayload is Map<String, dynamic>
        ? yearPayload['year']
        : raw['year'];
    final categories = <String>[...genres];
    if (year is num) categories.add(year.toInt().toString());
    if (year is String && year.trim().isNotEmpty) categories.add(year.trim());

    return MediaItem(
      id: 'anilibria:$id',
      title: title.trim(),
      type: 'Аниме',
      posterUrl: _absoluteUrl(posterUrl),
      rating: rating.clamp(0, 10).toDouble(),
      voiceovers: const [],
      videoUrl: '',
      categories: List<String>.unmodifiable(categories),
      description: description,
    );
  }

  String _absoluteUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return '';
    if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return uri.toString();
    }
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    return '';
  }

  String _plainText(String value) => value
      .replaceAll(
        RegExp(r'<(script|style)\b[^>]*>[\s\S]*?</\1>', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Minimal transport exception that does not expose request credentials.
class HttpException implements Exception {
  const HttpException(this.message);

  final String message;

  @override
  String toString() => message;
}
