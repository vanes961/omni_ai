import 'package:omni_ai/features/media/data/media_item.dart';

/// Describes the media categories a source can return.
enum MediaSourceKind { movie, series, anime, manga }

/// One independently replaceable catalog/search integration.
///
/// Implementations should use official/public APIs or permitted feeds,
/// enforce request timeouts, and return catalog metadata only. A playable
/// URL must never be inferred from a poster or catalog page.
abstract interface class MediaSource {
  /// Stable, lowercase identifier used for diagnostics and deduplication.
  String get id;

  /// Categories this source can search.
  Set<MediaSourceKind> get supportedKinds;

  /// Search this source. Implementations should return an empty list when the
  /// source has no matching entries, and throw on transport/parse failures.
  Future<List<MediaItem>> search(
    String query, {
    required MediaSourceKind kind,
  });
}
