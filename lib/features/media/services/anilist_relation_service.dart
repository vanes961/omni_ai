import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/cross_content_recommendation.dart';

/// Explicit, catalog-verified boundary between a MangaDex title and an
/// AniList adaptation. Boundaries are required because catalog relations alone
/// do not prove where a reader can safely switch without spoilers.
class VerifiedMangaAnimeBoundary {
  const VerifiedMangaAnimeBoundary({
    required this.sourceChapter,
    this.safeTargetEpisode,
  });

  final int sourceChapter;
  final int? safeTargetEpisode;

  bool get isValid =>
      sourceChapter >= 0 &&
      (safeTargetEpisode == null || safeTargetEpisode! >= 1);
}

/// Discovers AniList relation edges for a MangaDex title that advertises an
/// AniList ID. It only emits recommendations when a verified spoiler boundary
/// has been supplied for that exact target; it never guesses chapter mapping.
class AniListRelationService {
  AniListRelationService({
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client();

  static const String endpoint = 'https://graphql.anilist.co';
  final http.Client _client;
  final Duration timeout;

  Future<List<CrossContentRelation>> fetchMangaRelations({
    required String mangaDexId,
    required int aniListMangaId,
    required Map<String, VerifiedMangaAnimeBoundary> verifiedBoundaries,
  }) async {
    if (mangaDexId.trim().isEmpty || aniListMangaId < 1) {
      return const <CrossContentRelation>[];
    }
    final response = await _client
        .post(
          Uri.parse(endpoint),
          headers: const {
            'accept': 'application/json',
            'content-type': 'application/json',
            'User-Agent': 'OMNI_AI/1.0 (cross-content catalog client)',
          },
          body: jsonEncode({
            'query': r'''
              query MangaRelations($id: Int) {
                Media(id: $id, type: MANGA) {
                  id
                  relations {
                    edges {
                      relationType
                      node {
                        id
                        type
                        siteUrl
                      }
                    }
                  }
                }
              }
            ''',
            'variables': {'id': aniListMangaId},
          }),
        )
        .timeout(timeout);
    if (response.statusCode != 200) return const <CrossContentRelation>[];
    return parseMangaRelations(
      jsonDecode(response.body),
      mangaDexId: mangaDexId,
      verifiedBoundaries: verifiedBoundaries,
    );
  }

  /// Parser exposed for deterministic tests; boundaries must come from a
  /// verified mapping source and are keyed by canonical target ID.
  static List<CrossContentRelation> parseMangaRelations(
    Object? payload, {
    required String mangaDexId,
    required Map<String, VerifiedMangaAnimeBoundary> verifiedBoundaries,
  }) {
    if (mangaDexId.trim().isEmpty || payload is! Map<String, dynamic>) {
      return const <CrossContentRelation>[];
    }
    final data = payload['data'];
    final media = data is Map<String, dynamic> ? data['Media'] : null;
    final relations = media is Map<String, dynamic> ? media['relations'] : null;
    final edges = relations is Map<String, dynamic> ? relations['edges'] : null;
    if (edges is! List) return const <CrossContentRelation>[];

    final sourceId = 'mangadex:$mangaDexId';
    final sourceUrl = 'https://mangadex.org/title/$mangaDexId';
    final output = <CrossContentRelation>[];
    final seen = <String>{};
    for (final raw in edges) {
      if (raw is! Map<String, dynamic>) continue;
      final relationType = raw['relationType'];
      final node = raw['node'];
      if (node is! Map<String, dynamic>) continue;
      final targetRawId = node['id'];
      final targetTypeRaw = node['type'];
      if (targetRawId is! int || targetRawId < 1) continue;
      final CrossContentType? targetType = switch (targetTypeRaw) {
        'ANIME' => CrossContentType.anime,
        'MANGA' => CrossContentType.manga,
        _ => null,
      };
      if (targetType == null) continue;
      final targetId = targetType == CrossContentType.anime
          ? 'anilist:anime:$targetRawId'
          : 'anilist:manga:$targetRawId';
      final boundary = verifiedBoundaries[targetId];
      if (boundary == null || !boundary.isValid || !seen.add(targetId)) {
        continue;
      }
      final kind = switch (relationType) {
        'ADAPTATION' => CrossContentRelationKind.adaptation,
        'SOURCE' => CrossContentRelationKind.sourceMaterial,
        'PREQUEL' => CrossContentRelationKind.prequel,
        'SEQUEL' => CrossContentRelationKind.sequel,
        'SPIN_OFF' => CrossContentRelationKind.spinOff,
        _ => null,
      };
      if (kind == null) continue;
      final targetUrl = node['siteUrl'];
      final uri = targetUrl is String ? Uri.tryParse(targetUrl) : null;
      if (uri == null || uri.scheme != 'https' || uri.host != 'anilist.co') {
        continue;
      }
      output.add(
        CrossContentRelation(
          sourceId: sourceId,
          targetId: targetId,
          sourceType: CrossContentType.manga,
          targetType: targetType,
          kind: kind,
          sourceName: 'AniList',
          sourceUrl: sourceUrl,
          confidence: 0.95,
          requiredSourceChapter: boundary.sourceChapter,
          safeTargetEpisode: targetType == CrossContentType.anime
              ? boundary.safeTargetEpisode
              : null,
        ),
      );
    }
    return List<CrossContentRelation>.unmodifiable(output);
  }

  void close() => _client.close();
}
