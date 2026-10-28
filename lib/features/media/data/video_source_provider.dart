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

/// A real playback option returned by a configured source provider.
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

  /// A magnet is a resolver input, never a URL for video_player itself.
  /// Only a valid hexadecimal BitTorrent info hash is accepted.
  bool get isMagnetSource {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'magnet') return false;
    final topics = uri.queryParametersAll['xt'] ?? const <String>[];
    for (final topic in topics) {
      const prefix = 'urn:btih:';
      if (!topic.toLowerCase().startsWith(prefix)) continue;
      final hash = topic.substring(prefix.length).toLowerCase();
      final isHex = hash.length == 40 &&
          hash.codeUnits.every(
            (unit) =>
                (unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102),
          );
      if (isHex) return true;
    }
    return false;
  }

  /// Torrent sources must be resolved to HTTP by a configured playback bridge.
  bool get isSupportedSource => isHttpStream || isMagnetSource;

  bool get hasHttpSubtitles {
    final value = subtitleUrl;
    if (value == null || value.trim().isEmpty) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// Bridges HTTP variants to the existing media-card model. Magnet inputs
  /// intentionally remain in the resolver layer and are not exposed as URLs.
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

/// Result of resolving playback options.
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
