import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

/// Compact chapter selector and progress overlay for a continuous manga reader.
///
/// Place it in the reader's [Stack]. [chapters] should contain the complete
/// chapter list in reading order and use stable IDs across refreshes.
class MangaReaderProgressOverlay extends StatelessWidget {
  const MangaReaderProgressOverlay({
    required this.chapterLabel,
    required this.currentPage,
    required this.totalPages,
    this.chapters = const [],
    this.onChapterSelected,
    super.key,
  });

  final String chapterLabel;
  final int currentPage;
  final int totalPages;
  final List<MangaReaderChapterOption> chapters;
  final ValueChanged<MangaReaderChapterOption>? onChapterSelected;

  int get _safeTotalPages => totalPages < 0 ? 0 : totalPages;

  int get _safeCurrentPage {
    if (_safeTotalPages == 0) return 0;
    return currentPage.clamp(1, _safeTotalPages);
  }

  double? get _progress => _safeTotalPages == 0
      ? null
      : (_safeCurrentPage / _safeTotalPages).clamp(0.0, 1.0).toDouble();

  Future<void> _openChapterPicker(BuildContext context) async {
    if (chapters.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111714),
      builder: (sheetContext) => _ChapterPickerSheet(
        chapters: chapters,
        currentChapterLabel: chapterLabel,
        onSelected: (chapter) {
          Navigator.of(sheetContext).pop();
          onChapterSelected?.call(chapter);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chapter = chapterLabel.trim();
    final chapterText = chapter.isEmpty ? 'Чтение' : 'Гл. $chapter';

    return Positioned(
      top: 8,
      right: 8,
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 142),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xE6111714),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x6674D69A), width: 0.7),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      key: const ValueKey('manga-reader-chapter-picker'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: chapters.isEmpty
                          ? null
                          : () => _openChapterPicker(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.menu_book_rounded,
                              size: 13,
                              color: Color(0xFF9BE6B4),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              chapterText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFF1F7F2),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (chapters.isNotEmpty) ...[
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.expand_more_rounded,
                                size: 14,
                                color: Color(0xFFB9C9BE),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_safeTotalPages > 0) ...[
                      const SizedBox(width: 7),
                      Text(
                        '$_safeCurrentPage/$_safeTotalPages',
                        style: const TextStyle(
                          color: Color(0xFFB9C9BE),
                          fontSize: 9,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
                if (_safeTotalPages > 0) ...[
                  const SizedBox(height: 5),
                  SizedBox(
                    width: 116,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 2,
                        backgroundColor: const Color(0xFF354139),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF74D69A),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MangaReaderChapterOption {
  const MangaReaderChapterOption({
    required this.id,
    required this.label,
    this.title,
  });

  final String id;
  final String label;
  final String? title;
}

class _ChapterPickerSheet extends StatelessWidget {
  const _ChapterPickerSheet({
    required this.chapters,
    required this.currentChapterLabel,
    required this.onSelected,
  });

  final List<MangaReaderChapterOption> chapters;
  final String currentChapterLabel;
  final ValueChanged<MangaReaderChapterOption> onSelected;

  @override
  Widget build(BuildContext context) {
    final currentLabel = currentChapterLabel.trim();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 34,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF526057),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                const Icon(Icons.menu_book_rounded, color: Color(0xFF9BE6B4)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Все главы',
                    style: TextStyle(
                      color: Color(0xFFF1F7F2),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${chapters.length}',
                  style: const TextStyle(
                    color: Color(0xFFB9C9BE),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF29332D)),
          Expanded(
            child: ListView.builder(
              key: const ValueKey('manga-reader-chapter-list'),
              itemCount: chapters.length,
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                final isCurrent = chapter.label.trim() == currentLabel;

                return ListTile(
                  key: ValueKey('manga-chapter-${chapter.id}'),
                  dense: true,
                  title: Text(
                    'Глава ${chapter.label}',
                    style: TextStyle(
                      color: isCurrent
                          ? const Color(0xFF9BE6B4)
                          : const Color(0xFFF1F7F2),
                      fontSize: 14,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  subtitle:
                      chapter.title == null || chapter.title!.trim().isEmpty
                      ? null
                      : Text(
                          chapter.title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF9CAAA0),
                            fontSize: 12,
                          ),
                        ),
                  trailing: isCurrent
                      ? const Icon(
                          Icons.play_arrow_rounded,
                          color: Color(0xFF74D69A),
                        )
                      : null,
                  onTap: () => onSelected(chapter),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
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
      sourceChapter >= 1 &&
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
