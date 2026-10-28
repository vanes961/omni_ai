import 'package:omni_ai/features/media/data/media_item.dart';

/// Media type requested from a playback resolver.
enum PlaybackMediaKind { movie, series, anime }

/// Identifies a title or episode without coupling playback to a catalog vendor.
class PlaybackRequest {
  const PlaybackRequest({
    required this.mediaId,
    required this.title,
    required this.kind,
    this.season,
    this.episode,
    this.releaseYear,
  });

  /// Stable app/catalog ID, for example `kinopoisk:123` or `tmdb:movie:123`.
  final String mediaId;
  final String title;
  final PlaybackMediaKind kind;
  final int? season;
  final int? episode;
  final int? releaseYear;

  bool get targetsEpisode =>
      kind == PlaybackMediaKind.series &&
      season != null &&
      season! > 0 &&
      episode != null &&
      episode! > 0;
}

/// A real playable option returned by a permitted source.
///
/// Do not construct URLs from catalog IDs or mark a source playable until a
/// provider has returned a concrete HTTP(S) stream URL.
class PlaybackVariant {
  const PlaybackVariant({
    required this.url,
    this.quality,
    this.voiceover,
    this.subtitleUrl,
    this.format,
    this.headers = const {},
  });

  final String url;
  final String? quality;
  final String? voiceover;
  final String? subtitleUrl;
  final String? format;

  /// Only provider-required, non-secret playback headers belong here.
  final Map<String, String> headers;

  bool get isHttpStream {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// Magnet links are accepted only as resolver inputs. The player must turn
  /// them into an HTTP stream through an explicitly configured torrent bridge;
  /// they are never passed directly to video_player.
  bool get isMagnetSource {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'magnet') return false;
    final topics = uri.queryParametersAll['xt'] ?? const <String>[];
    return topics.any((topic) =>
        RegExp(r'^urn:btih:(?:[a-fA-F0-9]{40}|[a-zA-Z2-7]{32})
    final value = subtitleUrl;
    if (value == null || value.trim().isEmpty) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// Bridges the normalized playback model to the existing media-card model.
  /// Invalid URLs are intentionally not exposed as player options.
  MediaVideoSource? toMediaVideoSource() {
    if (!isHttpStream) return null;
    return MediaVideoSource(
      url: url,
      quality: quality?.trim().isNotEmpty == true ? quality!.trim() : 'Auto',
      voiceover: voiceover?.trim().isNotEmpty == true
          ? voiceover!.trim()
          : null,
    );
  }
}

/// Result of resolving playback options. Empty variants means no playable
/// stream was found; it must not be represented as successful playback.
class PlaybackResolution {
  PlaybackResolution({
    required this.providerId,
    required Iterable<PlaybackVariant> variants,
    this.message,
  }) : variants = List<PlaybackVariant>.unmodifiable(
         variants.where((variant) => variant.isSupportedSource),
       );

  final String providerId;
  final List<PlaybackVariant> variants;
  final String? message;

  bool get hasPlayableVariants => variants.isNotEmpty;
}

/// Plug-in boundary for independently replaceable, authorized video sources.
///
/// Implementations should use documented/permissioned endpoints, apply
/// timeouts, and never bypass DRM or access controls. Catalog sources such as
/// PoiskKino are metadata providers and should not implement this interface
/// unless they genuinely return playable streams.
abstract interface class VideoSourceProvider {
  String get id;

  Future<PlaybackResolution> resolve(PlaybackRequest request);
}
)
            .hasMatch(topic));
  }

  bool get isSupportedSource => isHttpStream || isMagnetSource;

  bool get hasHttpSubtitles {
    final value = subtitleUrl;
    if (value == null || value.trim().isEmpty) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// Bridges the normalized playback model to the existing media-card model.
  /// Invalid URLs are intentionally not exposed as player options.
  MediaVideoSource? toMediaVideoSource() {
    if (!isHttpStream) return null;
    return MediaVideoSource(
      url: url,
      quality: quality?.trim().isNotEmpty == true ? quality!.trim() : 'Auto',
      voiceover: voiceover?.trim().isNotEmpty == true
          ? voiceover!.trim()
          : null,
    );
  }
}

/// Result of resolving playback options. Empty variants means no playable
/// stream was found; it must not be represented as successful playback.
class PlaybackResolution {
  PlaybackResolution({
    required this.providerId,
    required Iterable<PlaybackVariant> variants,
    this.message,
  }) : variants = List<PlaybackVariant>.unmodifiable(
         variants.where((variant) => variant.isHttpStream),
       );

  final String providerId;
  final List<PlaybackVariant> variants;
  final String? message;

  bool get hasPlayableVariants => variants.isNotEmpty;
}

/// Plug-in boundary for independently replaceable, authorized video sources.
///
/// Implementations should use documented/permissioned endpoints, apply
/// timeouts, and never bypass DRM or access controls. Catalog sources such as
/// PoiskKino are metadata providers and should not implement this interface
/// unless they genuinely return playable streams.
abstract interface class VideoSourceProvider {
  String get id;

  Future<PlaybackResolution> resolve(PlaybackRequest request);
}
