import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/sources/media_source.dart';

/// Catalog metadata adapter for PoiskKino API (Kinopoisk/TMDb/IMDb data).
///
/// The API key must be supplied by the app's credential store or explicitly
/// injected by the caller. No credentials are embedded in source code.
/// This adapter never treats catalog URLs as playable video streams.
class KinopoiskCatalogSource implements MediaSource {
  KinopoiskCatalogSource({
    required this.apiKey,
    this.client,
    Uri? baseUri,
    this.timeout = const Duration(seconds: 10),
  }) : baseUri = baseUri ?? Uri.https('api.poiskkino.dev', '/v1.5/movie/search');

  final String apiKey;
  final http.Client? client;
  final Uri baseUri;
  final Duration timeout;

  @override
  String get id => 'kinopoisk';

  @override
  Set<MediaSourceKind> get supportedKinds =>
      const {MediaSourceKind.movie, MediaSourceKind.series};

  Future<http.Response> _get(Uri uri) {
    final transport = client;
    return (transport == null
            ? http.get(uri, headers: _headers)
            : transport.get(uri, headers: _headers))
        .timeout(timeout);
  }

  Map<String, String> get _headers => {
    'X-API-KEY': apiKey.trim(),
    'accept': 'application/json',
  };

  @override
  Future<List<MediaItem>> search(
    String query, {
    required MediaSourceKind kind,
  }) async {
    final normalizedQuery = query.trim();
    if (!supportedKinds.contains(kind) ||
        normalizedQuery.isEmpty ||
        apiKey.trim().isEmpty) {
      return const <MediaItem>[];
    }

    final uri = baseUri.replace(
      queryParameters: {
        ...baseUri.queryParameters,
        'query': normalizedQuery,
        'page': '1',
        'limit': '10',
      },
    );
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw CatalogHttpException(
        'PoiskKino returned HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final entries = _extractEntries(decoded);
    final items = <MediaItem>[];
    for (final raw in entries) {
      final item = _toMediaItem(raw, requestedKind: kind);
      if (item != null) items.add(item);
    }
    return List<MediaItem>.unmodifiable(items);
  }

  /// Loads one catalog record by its PoiskKino ID for the details screen.
  /// This returns metadata only and never a playback URL.
  Future<Map<String, dynamic>?> fetchDetails(String id) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty || apiKey.trim().isEmpty) return null;
    final uri = Uri.https(
      'api.poiskkino.dev',
      '/v1.5/movie/${Uri.encodeComponent(normalizedId)}',
    );
    final response = await _get(uri);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw CatalogHttpException(
        'PoiskKino returned HTTP ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      final nested = decoded['data'] ?? decoded['result'];
      if (nested is Map<String, dynamic>) return nested;
      if (decoded.containsKey('id')) return decoded;
    }
    return null;
  }

  /// Loads a rating-sorted catalog list for discovery sections.
  /// Uses the API's filtered movie endpoint rather than fabricating trending
  /// titles when TMDB is unavailable.
  Future<List<MediaItem>> fetchPopular({
    required MediaSourceKind kind,
    int limit = 20,
  }) async {
    if (!supportedKinds.contains(kind) || apiKey.trim().isEmpty) {
      return const <MediaItem>[];
    }
    final uri = Uri.https('api.poiskkino.dev', '/v1.5/movie', {
      'type': kind == MediaSourceKind.series ? 'tv-series' : 'movie',
      'sortField': 'rating.kp',
      'sortType': '-1',
      'limit': limit.clamp(1, 10).toString(),
      'notNullFields': 'name',
    });
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw CatalogHttpException(
        'PoiskKino returned HTTP ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final entries = _extractEntries(decoded);
    final items = <MediaItem>[];
    for (final raw in entries) {
      final item = _toMediaItem(raw, requestedKind: kind);
      if (item != null) items.add(item);
    }
    return List<MediaItem>.unmodifiable(items);
  }

  /// Loads recommendations matching catalog genre names. Genre filters are
  /// repeated query parameters as documented by PoiskKino's v1.5 API.
  Future<List<MediaItem>> fetchByGenres({
    required MediaSourceKind kind,
    required List<String> genres,
    int limit = 10,
  }) async {
    final normalizedGenres = genres
        .map((genre) => genre.trim())
        .where((genre) => genre.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (!supportedKinds.contains(kind) ||
        apiKey.trim().isEmpty ||
        normalizedGenres.isEmpty) {
      return const <MediaItem>[];
    }

    final uri = Uri.https('api.poiskkino.dev', '/v1.5/movie', {
      'type': kind == MediaSourceKind.series ? 'tv-series' : 'movie',
      'genres.name': normalizedGenres,
      'sortField': 'rating.kp',
      'sortType': '-1',
      'limit': limit.clamp(1, 10).toString(),
      'notNullFields': 'name',
    });
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw CatalogHttpException(
        'PoiskKino returned HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final items = <MediaItem>[];
    for (final raw in _extractEntries(decoded)) {
      final item = _toMediaItem(raw, requestedKind: kind);
      if (item != null) items.add(item);
    }
    return List<MediaItem>.unmodifiable(items);
  }

  List<Map<String, dynamic>> _extractEntries(Object? decoded) {
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    if (decoded is! Map<String, dynamic>) return const [];
    // SearchMovieResponseDtoV1_4 and compatible deployments have used
    // different envelope names. Accept common list fields, including the
    // `films` key used by some wrappers, without assuming arbitrary values
    // are media records.
    for (final key in const [
      'docs',
      'results',
      'items',
      'data',
      'films',
      'movies',
    ]) {
      final value = decoded[key];
      if (value is List) {
        return value.whereType<Map<String, dynamic>>().toList();
      }
    }
    // Some API gateways wrap the upstream payload in `result` or an object
    // under `data`. Unwrap one layer and run the same strict extraction.
    for (final key in const ['result', 'data']) {
      final value = decoded[key];
      if (value is Map<String, dynamic>) {
        final nested = _extractEntries(value);
        if (nested.isNotEmpty) return nested;
      }
    }
    // A details-shaped response is accepted for API versions that return one
    // matching record directly.
    if (decoded.containsKey('id') &&
        (decoded.containsKey('name') || decoded.containsKey('names'))) {
      return [decoded];
    }
    return const [];
  }

  MediaItem? _toMediaItem(
    Map<String, dynamic> raw, {
    required MediaSourceKind requestedKind,
  }) {
    final id = raw['id'];
    final title = _title(raw);
    if (id == null || title.isEmpty) return null;

    final rawType = (raw['type'] as String? ?? '').toLowerCase();
    final isSeries = raw['isSeries'] == true ||
        const {'tv-series', 'animated-series'}.contains(rawType);
    if (requestedKind == MediaSourceKind.series && !isSeries) return null;
    if (requestedKind == MediaSourceKind.movie && isSeries) return null;

    final poster = raw['poster'];
    final posterMap = poster is Map<String, dynamic> ? poster : const {};
    final posterUrl = _httpUrl(
      posterMap['url'] as String? ??
          raw['posterUrl'] as String? ??
          raw['poster_url'] as String? ??
          '',
    );

    final ratingPayload = raw['rating'];
    final ratingMap =
        ratingPayload is Map<String, dynamic> ? ratingPayload : const {};
    final ratingValue = ratingPayload is num
        ? ratingPayload
        : ratingMap['kp'] ?? ratingMap['imdb'] ?? ratingMap['tmdb'];
    final rating = ratingValue is num ? ratingValue.toDouble() : 0.0;

    final genrePayload = raw['genres'];
    final genres = genrePayload is List
        ? genrePayload
              .map((value) => value is Map<String, dynamic>
                  ? value['name'] as String?
                  : value is String
                      ? value
                      : null)
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList()
        : <String>[];
    final year = raw['year'];
    if (year is num) genres.add(year.toInt().toString());

    final description = (raw['description'] as String? ??
            raw['shortDescription'] as String? ??
            raw['short_description'] as String? ??
            '')
        .trim();

    return MediaItem(
      id: 'kinopoisk:$id',
      title: title,
      type: requestedKind == MediaSourceKind.series ? 'Сериал' : 'Фильм',
      posterUrl: posterUrl,
      rating: rating.clamp(0, 10).toDouble(),
      voiceovers: const [],
      videoUrl: '',
      categories: List<String>.unmodifiable(genres),
      description: description,
    );
  }

  String _title(Map<String, dynamic> raw) {
    final direct = (raw['name'] as String? ??
            raw['alternativeName'] as String? ??
            raw['alternative_name'] as String? ??
            '')
        .trim();
    if (direct.isNotEmpty) return direct;
    final names = raw['names'];
    if (names is List) {
      for (final entry in names) {
        if (entry is Map<String, dynamic>) {
          final name = (entry['name'] as String? ?? '').trim();
          if (name.isNotEmpty) return name;
        }
      }
    }
    return '';
  }

  String _httpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return '';
    }
    return uri.toString();
  }
}

/// Does not include request URLs or API credentials in its error message.
class CatalogHttpException implements Exception {
  const CatalogHttpException(this.message);

  final String message;

  @override
  String toString() => message;
}
