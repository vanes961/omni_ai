import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/sources/media_source.dart';

/// Public Jikan API: MyAnimeList metadata for anime and manga.
class JikanCatalogSource implements MediaSource {
  JikanCatalogSource({this.client, this.timeout = const Duration(seconds: 10)});
  final http.Client? client;
  final Duration timeout;
  @override String get id => 'jikan';
  @override Set<MediaSourceKind> get supportedKinds => const {MediaSourceKind.anime, MediaSourceKind.manga};

  @override
  Future<List<MediaItem>> search(String query, {required MediaSourceKind kind}) async {
    if (!supportedKinds.contains(kind) || query.trim().isEmpty) return const [];
    final path = kind == MediaSourceKind.anime ? '/v4/anime' : '/v4/manga';
    final uri = Uri.https('api.jikan.moe', path, {'q': query.trim(), 'limit': '20', 'sfw': 'true'});
    final response = await _get(uri);
    if (response.statusCode != 200) throw CatalogSourceException('Jikan HTTP ' + response.statusCode.toString());
    final json = jsonDecode(response.body);
    final rows = json is Map<String, dynamic> && json['data'] is List ? json['data'] as List : const [];
    return _mapRows(rows, kind, 'jikan');
  }
  Future<http.Response> _get(Uri uri) {
    final headers = const {'accept': 'application/json', 'User-Agent': 'OMNI-AI/1.0'};
    return (client == null ? http.get(uri, headers: headers) : client!.get(uri, headers: headers)).timeout(timeout);
  }
}

/// Public AniList GraphQL API for anime and manga metadata.
class AniListCatalogSource implements MediaSource {
  AniListCatalogSource({this.client, this.timeout = const Duration(seconds: 10)});
  final http.Client? client;
  final Duration timeout;
  @override String get id => 'anilist';
  @override Set<MediaSourceKind> get supportedKinds => const {MediaSourceKind.anime, MediaSourceKind.manga};

  @override
  Future<List<MediaItem>> search(String query, {required MediaSourceKind kind}) async {
    if (!supportedKinds.contains(kind) || query.trim().isEmpty) return const [];
    const gql = r'query ($search: String, $type: MediaType) { Page(page: 1, perPage: 20) { media(search: $search, type: $type, isAdult: false) { id siteUrl description averageScore genres seasonYear title { romaji english native } coverImage { large extraLarge } } } }';
    final body = jsonEncode({'query': gql, 'variables': {'search': query.trim(), 'type': kind == MediaSourceKind.anime ? 'ANIME' : 'MANGA'}});
    final headers = const {'content-type': 'application/json', 'accept': 'application/json'};
    final uri = Uri.https('graphql.anilist.co', '/');
    final response = await (client == null ? http.post(uri, headers: headers, body: body) : client!.post(uri, headers: headers, body: body)).timeout(timeout);
    if (response.statusCode != 200) throw CatalogSourceException('AniList HTTP ' + response.statusCode.toString());
    final json = jsonDecode(response.body);
    final data = json is Map<String, dynamic> ? json['data'] : null;
    final page = data is Map<String, dynamic> ? data['Page'] : null;
    final rows = page is Map<String, dynamic> && page['media'] is List ? page['media'] as List : const [];
    final items = <MediaItem>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final titles = row['title'] is Map<String, dynamic> ? row['title'] as Map<String, dynamic> : const <String, dynamic>{};
      final title = _first([titles['english'], titles['romaji'], titles['native']]);
      if (title.isEmpty || row['id'] == null) continue;
      final cover = row['coverImage'] is Map<String, dynamic> ? row['coverImage'] as Map<String, dynamic> : const <String, dynamic>{};
      final genres = (row['genres'] as List? ?? const []).whereType<String>().toList();
      if (row['seasonYear'] is num) genres.add((row['seasonYear'] as num).toInt().toString());
      final score = (row['averageScore'] as num?)?.toDouble() ?? 0;
      items.add(MediaItem(id: 'anilist:' + kind.name + ':' + row['id'].toString(), title: title,
        type: kind == MediaSourceKind.anime ? 'Аниме' : 'Манга',
        posterUrl: _http(_first([cover['extraLarge'], cover['large']])),
        rating: (score / 10).clamp(0, 10).toDouble(), voiceovers: const [], videoUrl: '',
        categories: genres, description: _plain(row['description'] as String? ?? '')));
    }
    return List<MediaItem>.unmodifiable(items);
  }
}

/// Public Kitsu JSON:API catalog; read-only searches require no API key.
class KitsuCatalogSource implements MediaSource {
  KitsuCatalogSource({this.client, this.timeout = const Duration(seconds: 10)});
  final http.Client? client;
  final Duration timeout;
  @override String get id => 'kitsu';
  @override Set<MediaSourceKind> get supportedKinds => const {MediaSourceKind.anime, MediaSourceKind.manga};

  @override
  Future<List<MediaItem>> search(String query, {required MediaSourceKind kind}) async {
    if (!supportedKinds.contains(kind) || query.trim().isEmpty) return const [];
    final type = kind == MediaSourceKind.anime ? 'anime' : 'manga';
    final uri = Uri.https('kitsu.io', '/api/edge/' + type, {'filter[text]': query.trim(), 'page[limit]': '20'});
    final headers = const {'accept': 'application/vnd.api+json', 'User-Agent': 'OMNI-AI/1.0'};
    final response = await (client == null ? http.get(uri, headers: headers) : client!.get(uri, headers: headers)).timeout(timeout);
    if (response.statusCode != 200) throw CatalogSourceException('Kitsu HTTP ' + response.statusCode.toString());
    final json = jsonDecode(response.body);
    final rows = json is Map<String, dynamic> && json['data'] is List ? json['data'] as List : const [];
    final items = <MediaItem>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final a = row['attributes'] is Map<String, dynamic> ? row['attributes'] as Map<String, dynamic> : const <String, dynamic>{};
      final titles = a['titles'] is Map<String, dynamic> ? a['titles'] as Map<String, dynamic> : const <String, dynamic>{};
      final title = _first([a['canonicalTitle'], titles['en'], titles['en_jp'], titles['ja_jp'], a['slug']]);
      if (title.isEmpty || row['id'] == null) continue;
      final poster = a['posterImage'] is Map<String, dynamic> ? a['posterImage'] as Map<String, dynamic> : const <String, dynamic>{};
      final categories = <String>[];
      final date = a['startDate'] as String?;
      if (date != null && date.length >= 4) categories.add(date.substring(0, 4));
      final rating = double.tryParse((a['averageRating'] ?? '').toString()) ?? 0;
      items.add(MediaItem(id: 'kitsu:' + type + ':' + row['id'].toString(), title: title,
        type: kind == MediaSourceKind.anime ? 'Аниме' : 'Манга',
        posterUrl: _http(_first([poster['large'], poster['medium'], poster['small']])),
        rating: (rating / 10).clamp(0, 10).toDouble(), voiceovers: const [], videoUrl: '',
        categories: categories, description: _plain(a['synopsis'] as String? ?? '')));
    }
    return List<MediaItem>.unmodifiable(items);
  }
}

/// OMDb catalog adapter. It stays inactive until a key is supplied securely.
class OmdbCatalogSource implements MediaSource {
  OmdbCatalogSource({required this.apiKey, this.client, this.timeout = const Duration(seconds: 10)});
  final String apiKey;
  final http.Client? client;
  final Duration timeout;
  @override String get id => 'omdb';
  @override Set<MediaSourceKind> get supportedKinds => const {MediaSourceKind.movie, MediaSourceKind.series};

  @override
  Future<List<MediaItem>> search(String query, {required MediaSourceKind kind}) async {
    if (!supportedKinds.contains(kind) || query.trim().isEmpty || apiKey.trim().isEmpty) return const [];
    final uri = Uri.https('www.omdbapi.com', '/', {'apikey': apiKey.trim(), 's': query.trim(), 'type': kind == MediaSourceKind.movie ? 'movie' : 'series'});
    final response = await (client == null ? http.get(uri) : client!.get(uri)).timeout(timeout);
    if (response.statusCode != 200) throw CatalogSourceException('OMDb HTTP ' + response.statusCode.toString());
    final json = jsonDecode(response.body);
    final rows = json is Map<String, dynamic> && json['Search'] is List ? json['Search'] as List : const [];
    final items = <MediaItem>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final title = (row['Title'] as String? ?? '').trim();
      final id = (row['imdbID'] as String? ?? '').trim();
      if (title.isEmpty || id.isEmpty) continue;
      final year = (row['Year'] as String? ?? '').trim();
      items.add(MediaItem(id: 'omdb:' + id, title: title,
        type: kind == MediaSourceKind.movie ? 'Фильм' : 'Сериал',
        posterUrl: _http(row['Poster'] as String? ?? ''), rating: 0, voiceovers: const [], videoUrl: '',
        categories: year.isEmpty ? const [] : [year], description: ''));
    }
    return List<MediaItem>.unmodifiable(items);
  }
}

/// Wikidata fallback search, free and keyless; results are metadata only.
class WikidataCatalogSource implements MediaSource {
  WikidataCatalogSource({this.client, this.timeout = const Duration(seconds: 10)});
  final http.Client? client;
  final Duration timeout;
  @override String get id => 'wikidata';
  @override Set<MediaSourceKind> get supportedKinds => const {MediaSourceKind.movie, MediaSourceKind.series};

  @override
  Future<List<MediaItem>> search(String query, {required MediaSourceKind kind}) async {
    if (!supportedKinds.contains(kind) || query.trim().isEmpty) return const [];
    final uri = Uri.https('www.wikidata.org', '/w/api.php', {'action': 'wbsearchentities', 'search': query.trim(), 'language': 'ru', 'uselang': 'ru', 'type': 'item', 'limit': '20', 'format': 'json'});
    final headers = const {'accept': 'application/json', 'User-Agent': 'OMNI-AI/1.0 (public metadata catalog)'};
    final response = await (client == null ? http.get(uri, headers: headers) : client!.get(uri, headers: headers)).timeout(timeout);
    if (response.statusCode != 200) throw CatalogSourceException('Wikidata HTTP ' + response.statusCode.toString());
    final json = jsonDecode(response.body);
    final rows = json is Map<String, dynamic> && json['search'] is List ? json['search'] as List : const [];
    final items = <MediaItem>[];
    for (final row in rows) {
      if (row is! Map<String, dynamic>) continue;
      final id = (row['id'] as String? ?? '').trim();
      final title = (row['label'] as String? ?? '').trim();
      if (id.isEmpty || title.isEmpty) continue;
      items.add(MediaItem(id: 'wikidata:' + id, title: title,
        type: kind == MediaSourceKind.movie ? 'Фильм' : 'Сериал',
        posterUrl: '', rating: 0, voiceovers: const [], videoUrl: '', categories: const [],
        description: _plain(row['description'] as String? ?? '')));
    }
    return List<MediaItem>.unmodifiable(items);
  }
}

class CatalogSourceException implements Exception {
  const CatalogSourceException(this.message);
  final String message;
  @override String toString() => message;
}

List<MediaItem> _mapRows(List rows, MediaSourceKind kind, String sourceId) {
  final items = <MediaItem>[];
  for (final row in rows) {
    if (row is! Map<String, dynamic>) continue;
    final id = row['mal_id'] ?? row['id'];
    final title = _first([row['title_english'], row['title'], row['russian'], row['name']]);
    if (id == null || title.isEmpty) continue;
    final images = row['images'] is Map<String, dynamic> ? row['images'] as Map<String, dynamic> : const <String, dynamic>{};
    final jpg = images['jpg'] is Map<String, dynamic> ? images['jpg'] as Map<String, dynamic> : const <String, dynamic>{};
    final poster = row['poster'] is Map<String, dynamic> ? row['poster'] as Map<String, dynamic> : const <String, dynamic>{};
    final image = _first([jpg['large_image_url'], jpg['image_url'], poster['original'], poster['main']]);
    final categories = <String>[];
    for (final g in (row['genres'] as List? ?? const [])) {
      if (g is String) categories.add(g);
      if (g is Map<String, dynamic>) {
        final name = _first([g['name'], g['russian']]);
        if (name.isNotEmpty) categories.add(name);
      }
    }
    final year = row['year'] ?? row['aired_on'] ?? row['released_on'];
    if (year is num) categories.add(year.toInt().toString());
    if (year is String && year.length >= 4) categories.add(year.substring(0, 4));
    final score = row['score'];
    final rating = score is num ? score.toDouble() : double.tryParse((score ?? '').toString()) ?? 0;
    items.add(MediaItem(id: sourceId + ':' + id.toString(), title: title,
      type: kind == MediaSourceKind.anime ? 'Аниме' : 'Манга',
      posterUrl: _http(image), rating: rating.clamp(0, 10).toDouble(),
      voiceovers: const [], videoUrl: '', categories: categories,
      description: _plain(row['synopsis'] as String? ?? row['description'] as String? ?? '')));
  }
  return List<MediaItem>.unmodifiable(items);
}

String _first(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return '';
}
String _http(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty ? uri.toString() : '';
}
String _plain(String value) => value
    .replaceAll(RegExp(r'<(script|style)\b[^>]*>[\s\S]*?</\1>', caseSensitive: false), ' ')
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();


/// Public Shikimori REST catalog for Russian-language anime and manga metadata.
class ShikimoriCatalogSource implements MediaSource {
  ShikimoriCatalogSource({this.client, this.timeout = const Duration(seconds: 10)});
  final http.Client? client;
  final Duration timeout;
  @override String get id => 'shikimori';
  @override Set<MediaSourceKind> get supportedKinds => const {MediaSourceKind.anime, MediaSourceKind.manga};

  @override
  Future<List<MediaItem>> search(String query, {required MediaSourceKind kind}) async {
    if (!supportedKinds.contains(kind) || query.trim().isEmpty) return const [];
    final endpoint = kind == MediaSourceKind.anime ? 'animes' : 'mangas';
    final uri = Uri.https('shikimori.one', '/api/' + endpoint, {'search': query.trim(), 'limit': '20'});
    final headers = const {'accept': 'application/json', 'User-Agent': 'OMNI-AI/1.0 (catalog search)'};
    final response = await (client == null ? http.get(uri, headers: headers) : client!.get(uri, headers: headers)).timeout(timeout);
    if (response.statusCode != 200) throw CatalogSourceException('Shikimori HTTP ' + response.statusCode.toString());
    final json = jsonDecode(response.body);
    return _mapRows(json is List ? json : const [], kind, 'shikimori');
  }
}
