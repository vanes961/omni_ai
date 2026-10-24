import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/sources/media_source.dart';
import 'package:omni_ai/features/media/sources/source_registry.dart';

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
  MediaSourceEngine(
    Iterable<MediaSource> sources, {
    this.sourceTimeout = const Duration(seconds: 12),
    this.cacheTtl = const Duration(minutes: 5),
    this.maxCacheEntries = 100,
  }) : registry = SourceRegistry(sources);

  /// Upper bound for one source request, even if an adapter forgets a timeout.
  final Duration sourceTimeout;

  /// Short-lived in-memory cache; persistent device storage can be added later.
  final Duration cacheTtl;

  /// Bounds memory usage on low-end phones.
  final int maxCacheEntries;

  final Map<String, _CachedSearch> _cache = {};

  /// Exposes safe per-source health state for diagnostics and UI.
  final SourceRegistry registry;

  List<MediaSource> get _sources => registry.sources;

  List<String> get sourceIds =>
      List<String>.unmodifiable(_sources.map((source) => source.id));

  Future<List<MediaItem>> search(
    String query, {
    required MediaSourceKind kind,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return const <MediaItem>[];

    final cacheKey = '${kind.name}|${normalizedQuery.toLowerCase()}';
    final now = DateTime.now();
    final cached = _cache[cacheKey];
    if (cached != null && now.difference(cached.savedAt) < cacheTtl) {
      return cached.items;
    }
    if (cached != null) _cache.remove(cacheKey);

    final matchingSources = registry.candidatesFor(kind);

    final results = await Future.wait(
      matchingSources.map((source) async {
        final stopwatch = Stopwatch()..start();
        try {
          final items = await source
              .search(normalizedQuery, kind: kind)
              .timeout(sourceTimeout);
          stopwatch.stop();
          registry.recordSuccess(
            source.id,
            checkedAt: DateTime.now(),
            latency: stopwatch.elapsed,
          );
          return MediaSourceResult(sourceId: source.id, items: items);
        } on Object catch (error) {
          stopwatch.stop();
          registry.recordFailure(
            source.id,
            checkedAt: DateTime.now(),
            latency: stopwatch.elapsed,
            errorCategory: _errorCategory(error),
          );
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
    final immutableItems = List<MediaItem>.unmodifiable(items);
    if (results.any((result) => result.succeeded) &&
        maxCacheEntries > 0 &&
        cacheTtl > Duration.zero) {
      if (_cache.length >= maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
      _cache[cacheKey] = _CachedSearch(immutableItems, DateTime.now());
    }
    return immutableItems;
  }

  /// Returns per-source health/results for diagnostics without exposing
  /// response bodies, tokens, or other request details.
  Future<List<MediaSourceResult>> inspect(
    String query, {
    required MediaSourceKind kind,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return const <MediaSourceResult>[];

    final matchingSources = registry.candidatesFor(kind);

    return List<MediaSourceResult>.unmodifiable(
      await Future.wait(
        matchingSources.map((source) async {
          final stopwatch = Stopwatch()..start();
          try {
            final items = await source
                .search(normalizedQuery, kind: kind)
                .timeout(sourceTimeout);
            stopwatch.stop();
            registry.recordSuccess(
              source.id,
              checkedAt: DateTime.now(),
              latency: stopwatch.elapsed,
            );
            return MediaSourceResult(sourceId: source.id, items: items);
          } on Object catch (error) {
            stopwatch.stop();
            registry.recordFailure(
              source.id,
              checkedAt: DateTime.now(),
              latency: stopwatch.elapsed,
              errorCategory: _errorCategory(error),
            );
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

  String _errorCategory(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('timeout')) return 'timeout';
    if (message.contains('socket') ||
        message.contains('network') ||
        message.contains('connection')) {
      return 'network';
    }
    if (message.contains('http')) return 'http';
    if (message.contains('format') ||
        message.contains('json') ||
        message.contains('parse')) {
      return 'parse';
    }
    return 'unknown';
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

class _CachedSearch {
  const _CachedSearch(this.items, this.savedAt);

  final List<MediaItem> items;
  final DateTime savedAt;
}
