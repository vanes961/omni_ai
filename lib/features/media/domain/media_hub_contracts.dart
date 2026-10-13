import 'package:flutter/foundation.dart';

/// Where catalog metadata comes from. Implementations must return real,
/// attributable records and must not manufacture placeholder media.
abstract interface class MediaCatalogProvider {
  Future<List<MediaCatalogEntry>> search(MediaCatalogQuery query);
}

/// A provider-independent search request for the OMNI media hub.
@immutable
class MediaCatalogQuery {
  const MediaCatalogQuery({required this.text, this.kind, this.page = 0})
    : assert(page >= 0);

  final String text;
  final MediaKind? kind;
  final int page;
}

enum MediaKind { film, series, anime, animation, documentary, trailer }

/// Metadata used by the hub before a playable source has been selected.
@immutable
class MediaCatalogEntry {
  const MediaCatalogEntry({
    required this.id,
    required this.title,
    required this.kind,
    required this.sourceName,
    this.year,
    this.description = '',
    this.posterUri,
    this.detailUri,
  });

  final String id;
  final String title;
  final MediaKind kind;
  final String sourceName;
  final int? year;
  final String description;
  final Uri? posterUri;
  final Uri? detailUri;
}

/// A playable source supplied by a user or a provider with a documented,
/// permitted integration. The hub never invents stream URLs.
@immutable
class MediaStreamSource {
  const MediaStreamSource({
    required this.id,
    required this.label,
    required this.uri,
    this.headers = const <String, String>{},
  });

  final String id;
  final String label;
  final Uri uri;
  final Map<String, String> headers;

  bool get isNetworkStream =>
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;

  bool get isMagnet => uri.scheme == 'magnet' && _hasBitTorrentHash(uri);

  bool get isSupportedInput => isNetworkStream || isMagnet;

  static bool _hasBitTorrentHash(Uri uri) {
    final topic = uri.queryParameters['xt']?.toLowerCase();
    const prefix = 'urn:btih:';
    if (topic == null || !topic.startsWith(prefix)) return false;

    final hash = topic.substring(prefix.length);
    final isHexHash =
        hash.length == 40 && RegExp(r'^[0-9a-f]+
    final isBase32Hash =
        hash.length == 32 && RegExp(r'^[a-z2-7]+$').hasMatch(hash);
    return isHexHash || isBase32Hash;
  }
}

enum MediaEngineState {
  idle,
  resolving,
  buffering,
  ready,
  playing,
  paused,
  completed,
  cancelled,
  failed,
}

@immutable
class MediaEngineSnapshot {
  const MediaEngineSnapshot({
    required this.state,
    this.bufferedBytes = 0,
    this.totalBytes,
    this.playbackUri,
    this.message,
  }) : assert(bufferedBytes >= 0),
       assert(totalBytes == null || totalBytes >= 0);

  final MediaEngineState state;
  final int bufferedBytes;
  final int? totalBytes;
  final Uri? playbackUri;
  final String? message;

  double? get bufferedFraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (bufferedBytes / total).clamp(0.0, 1.0);
  }
}

/// Streaming is deliberately separate from catalog search and player UI.
/// Concrete adapters must document their API and validate endpoint security.
abstract interface class MediaStreamingEngine {
  Future<bool> checkConnection();

  Future<MediaEngineSnapshot> open(
    MediaStreamSource source, {
    required String sessionId,
  });

  Future<void> cancel(String sessionId);

  Future<void> close(String sessionId);
}
).hasMatch(hash);
    final isBase32Hash =
        hash.length == 32 && RegExp(r'^[a-z2-7]+$').hasMatch(hash);
    return isHexHash || isBase32Hash;
  }
}

enum MediaEngineState {
  idle,
  resolving,
  buffering,
  ready,
  playing,
  paused,
  completed,
  cancelled,
  failed,
}

@immutable
class MediaEngineSnapshot {
  const MediaEngineSnapshot({
    required this.state,
    this.bufferedBytes = 0,
    this.totalBytes,
    this.playbackUri,
    this.message,
  }) : assert(bufferedBytes >= 0),
       assert(totalBytes == null || totalBytes >= 0);

  final MediaEngineState state;
  final int bufferedBytes;
  final int? totalBytes;
  final Uri? playbackUri;
  final String? message;

  double? get bufferedFraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (bufferedBytes / total).clamp(0.0, 1.0);
  }
}

/// Streaming is deliberately separate from catalog search and player UI.
/// Concrete adapters must document their API and validate endpoint security.
abstract interface class MediaStreamingEngine {
  Future<bool> checkConnection();

  Future<MediaEngineSnapshot> open(
    MediaStreamSource source, {
    required String sessionId,
  });

  Future<void> cancel(String sessionId);

  Future<void> close(String sessionId);
}
