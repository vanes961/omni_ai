import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/sources/media_source.dart';

/// Result of one source request. Errors are isolated so one broken provider
/// cannot make the entire media search fail.
class MediaSourceResult {
  const MediaSourceResult({
    required this.sourceId,
    required this.items,
    this.error,
  });

  final String sourceId;
  final List<MediaItem> items;
  final Object? error;

  bool get succeeded => error == null;
}

/// Aggregates independent media catalogs without coupling the UI to a vendor.
///
/// This engine deliberately does not scrape arbitrary websites or bypass
/// access controls. Add a source through [MediaSource] after verifying its
/// API/feed and usage terms. Playback resolution remains a separate concern.
class MediaSourceEngine {
  MediaSourceEngine(Iterable<MediaSource> sources)
    : _sources = List<MediaSource>.unmodifiable(sources);

  final List<MediaSource> _sources;

  List<String> get sourceIds =>
      List<String>.unmodifiable(_sources.map((source) => source.id));

  Future<List<MediaItem>> search(
    String query, {
    required MediaSourceKind kind,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return const <MediaItem>[];

    final matchingSources = _sources
        .where((source) => source.supportedKinds.contains(kind))
        .toList(growable: false);

    final results = await Future.wait(
      matchingSources.map((source) async {
        try {
          return MediaSourceResult(
            sourceId: source.id,
            items: await source.search(normalizedQuery, kind: kind),
          );
        } on Object catch (error) {
          return MediaSourceResult(
            sourceId: source.id,
            items: const <MediaItem>[],
            error: error,
          );
        }
      }),
    );

    final unique = <String, MediaItem>{};
    for (final item in results.expand((result) => result.items)) {
      if (!_matchesKind(item, kind)) continue;
      final key = _identityKey(item, kind);
      if (key.isEmpty) continue;

      final current = unique[key];
      if (current == null || _qualityScore(item) > _qualityScore(current)) {
        unique[key] = item;
      }
    }

    final items = unique.values.toList()
      ..sort((a, b) {
        final rating = b.rating.compareTo(a.rating);
        return rating != 0
            ? rating
            : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    return List<MediaItem>.unmodifiable(items);
  }

  /// Returns per-source health/results for diagnostics without exposing
  /// response bodies, tokens, or other request details.
  Future<List<MediaSourceResult>> inspect(
    String query, {
    required MediaSourceKind kind,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return const <MediaSourceResult>[];

    final matchingSources = _sources
        .where((source) => source.supportedKinds.contains(kind))
        .toList(growable: false);

    return List<MediaSourceResult>.unmodifiable(
      await Future.wait(
        matchingSources.map((source) async {
          try {
            final items = await source.search(normalizedQuery, kind: kind);
            return MediaSourceResult(sourceId: source.id, items: items);
          } on Object catch (error) {
            return MediaSourceResult(
              sourceId: source.id,
              items: const <MediaItem>[],
              error: error,
            );
          }
        }),
      ),
    );
  }

  bool _matchesKind(MediaItem item, MediaSourceKind kind) {
    final type = item.type.trim().toLowerCase();
    return switch (kind) {
      MediaSourceKind.movie => type == 'фильм' || type == 'movie',
      MediaSourceKind.series =>
        type == 'сериал' || type == 'series' || type == 'tv',
      MediaSourceKind.anime => type == 'аниме' || type == 'anime',
      MediaSourceKind.manga => type == 'манга' || type == 'manga',
    };
  }

  String _identityKey(MediaItem item, MediaSourceKind kind) {
    final title = item.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9а-яё]', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (title.isEmpty) return '';
    // The requested category is canonical, so «movie» and «Фильм» entries
    // from different sources can still be deduplicated.
    return '${kind.name}|$title';
  }

  int _qualityScore(MediaItem item) {
    var score = 0;
    if (item.posterUrl.trim().isNotEmpty) score += 4;
    if (item.description.trim().isNotEmpty) score += 2;
    if (item.categories.isNotEmpty) score += 1;
    if (item.rating > 0 && item.rating <= 10) score += 1;
    return score;
  }
}
