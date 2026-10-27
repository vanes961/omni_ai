import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omni_ai/features/media/sources/media_source.dart';
import 'package:omni_ai/features/media/sources/media_source_engine.dart';
import 'package:omni_ai/features/media/sources/public_catalog_sources.dart';

/// Public MangaDex catalogue metadata. This service does not download or
/// render chapter pages; it returns catalogue records and official outbound
/// links so reading can follow the source's own availability and policies.
class MangaCatalogItem {
  const MangaCatalogItem({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.sourceUrl,
    required this.coverUrl,
    required this.authors,
    this.year,
    this.anilistId,
  });

  final String id;
  final String title;
  final String description;
  final String status;
  final String sourceUrl;
  final String coverUrl;
  final List<String> authors;
  final int? year;

  /// Optional AniList cross-reference supplied by MangaDex metadata.
  final int? anilistId;

  String get canonicalId => id.contains(':') ? id : 'mangadex:$id';
}

class MangaCatalogService {
  MangaCatalogService({
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client();

  static const String attribution = 'Metadata provided by MangaDex.';
  static const String _api = 'https://api.mangadex.org';
  static const String _site = 'https://mangadex.org/title';
  static const String _covers = 'https://uploads.mangadex.org/covers';

  final http.Client _client;
  final Duration timeout;

  late final MediaSourceEngine _publicMangaSources = MediaSourceEngine([
    JikanCatalogSource(client: _client, timeout: timeout),
    AniListCatalogSource(client: _client, timeout: timeout),
    KitsuCatalogSource(client: _client, timeout: timeout),
    ShikimoriCatalogSource(client: _client, timeout: timeout),
  ]);

  Future<List<MangaCatalogItem>> search(String query, {int limit = 20}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const <MangaCatalogItem>[];
    final results = <MangaCatalogItem>[];
    // MangaDex is the primary source, but it must not take down search if the
    // service is unavailable or inaccessible from the user's network.
    try {
      final boundedLimit = limit.clamp(1, 50);
      final uri = Uri.parse('$_api/manga').replace(
        queryParameters: {
          'title': normalized,
          'limit': '$boundedLimit',
          'offset': '0',
          'contentRating[]': 'safe',
          'includes[]': ['cover_art', 'author'],
        },
      );
      final response = await _client.get(uri, headers: const {
        'accept': 'application/json',
        'User-Agent': 'OMNI-AI/1.0 (MangaDex catalogue client)',
      }).timeout(timeout);
      if (response.statusCode == 200) {
        results.addAll(parseSearchResponse(jsonDecode(response.body)));
      }
    } on Object {
      // Continue with independent public metadata APIs.
    }

    try {
      final catalogItems = await _publicMangaSources.search(
        normalized,
        kind: MediaSourceKind.manga,
      );
      for (final item in catalogItems) {
        final idParts = item.id.split(':');
        final source = idParts.first;
        final sourceId = idParts.length > 1 ? idParts.last : '';
        if (sourceId.isEmpty) continue;
        final sourceUrl = switch (source) {
          'jikan' => 'https://myanimelist.net/manga/$sourceId',
          'anilist' => 'https://anilist.co/manga/$sourceId',
          'kitsu' => 'https://kitsu.io/manga/$sourceId',
          'shikimori' => 'https://shikimori.one/mangas/$sourceId',
          _ => '',
        };
        if (sourceUrl.isEmpty) continue;
        results.add(MangaCatalogItem(
          id: item.id,
          title: item.title,
          description: item.description,
          status: '',
          sourceUrl: sourceUrl,
          coverUrl: item.posterUrl,
          authors: const [],
          year: item.categories
              .map((value) => int.tryParse(value))
              .whereType<int>()
              .firstOrNull,
          anilistId: source == 'anilist' ? int.tryParse(sourceId) : null,
        ));
      }
    } on Object {
      // Individual providers are isolated by MediaSourceEngine.
    }

    final seen = <String>{};
    final unique = <MangaCatalogItem>[];
    for (final item in results) {
      final key = item.title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (key.isNotEmpty && seen.add(key)) unique.add(item);
      if (unique.length >= limit.clamp(1, 50)) break;
    }
    return List<MangaCatalogItem>.unmodifiable(unique);
  }

  /// Public parser kept separate for deterministic tests and cache migration.
  static List<MangaCatalogItem> parseSearchResponse(Object? payload) {
    if (payload is! Map<String, dynamic> || payload['data'] is! List) {
      return const <MangaCatalogItem>[];
    }
    final items = <MangaCatalogItem>[];
    final seen = <String>{};
    for (final raw in payload['data'] as List) {
      if (raw is! Map<String, dynamic>) continue;
      final id = raw['id'];
      final attributes = raw['attributes'];
      if (id is! String ||
          id.trim().isEmpty ||
          attributes is! Map<String, dynamic> ||
          !seen.add(id)) {
        continue;
      }
      final titleMap = attributes['title'];
      final title = _localizedText(titleMap);
      if (title.isEmpty) continue;
      final description = _localizedText(attributes['description']);
      final relationships = (raw['relationships'] as List? ?? const [])
          .whereType<Map<String, dynamic>>();
      String? coverFile;
      final authors = <String>[];
      for (final relationship in relationships) {
        final type = relationship['type'];
        final relatedAttributes =
            relationship['attributes'] as Map<String, dynamic>?;
        if (type == 'cover_art') {
          coverFile = relatedAttributes?['fileName'] as String? ?? coverFile;
        } else if (type == 'author') {
          final name = (relatedAttributes?['name'] as String? ?? '').trim();
          if (name.isNotEmpty) authors.add(name);
        }
      }
      final yearRaw = attributes['year'];
      final year = yearRaw is num ? yearRaw.toInt() : null;
      final links = attributes['links'];
      final anilistRaw = links is Map<String, dynamic> ? links['al'] : null;
      final anilistId = anilistRaw is int
          ? anilistRaw
          : anilistRaw is String
          ? int.tryParse(anilistRaw)
          : null;
      final status = (attributes['status'] as String? ?? '').trim();
      final coverUrl = coverFile == null || coverFile.trim().isEmpty
          ? ''
          : '$_covers/$id/${Uri.encodeComponent(coverFile)}.256.jpg';
      items.add(
        MangaCatalogItem(
          id: id,
          title: title,
          description: description,
          status: status,
          sourceUrl: '$_site/$id',
          coverUrl: coverUrl,
          authors: List<String>.unmodifiable(authors.toSet()),
          year: year,
          anilistId: anilistId != null && anilistId > 0 ? anilistId : null,
        ),
      );
    }
    return List<MangaCatalogItem>.unmodifiable(items);
  }

  static String _localizedText(Object? value) {
    if (value is! Map<String, dynamic>) return '';
    for (final language in const ['ru', 'en', 'ja-ro', 'ja']) {
      final text = value[language];
      if (text is String && text.trim().isNotEmpty) return text.trim();
    }
    for (final text in value.values) {
      if (text is String && text.trim().isNotEmpty) return text.trim();
    }
    return '';
  }

  void close() => _client.close();
}
