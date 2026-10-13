class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.type,
    required this.posterUrl,
    required this.rating,
    required this.voiceovers,
    required this.videoUrl,
    this.videoFallbackUrls = const [],
    this.voiceoverVideoUrls = const {},
    this.posterFallbackUrls = const [],
    this.categories = const [],
    this.episodes = const [],
    this.description = '',
    this.malId,
    this.videoSources = const [],
  });

  final String id;
  final String title;
  final String type;
  final String posterUrl;
  final List<String> posterFallbackUrls;
  final double rating;
  final List<String> voiceovers;
  final String videoUrl;
  final List<String> videoFallbackUrls;
  final Map<String, String> voiceoverVideoUrls;
  final List<String> categories;
  final List<MediaEpisode> episodes;
  final String description;

  /// MyAnimeList ID required by AniSkip; never populate with a TMDB ID.
  final int? malId;
  final List<MediaVideoSource> videoSources;
}

class MediaEpisode {
  const MediaEpisode({
    required this.number,
    required this.title,
    required this.videoUrl,
    this.videoFallbackUrls = const [],
    this.voiceoverVideoUrls = const {},
    this.videoSources = const [],
    this.seasonNumber = 1,
  });

  final int number;
  final String title;
  final String videoUrl;
  final List<String> videoFallbackUrls;
  final Map<String, String> voiceoverVideoUrls;
  final List<MediaVideoSource> videoSources;
  final int seasonNumber;

  String get label => 'СЕРИЯ ${number.toString().padLeft(2, '0')}  //  $title';
}

/// A concrete stream variant exposed by a media source resolver.
///
/// Quality choices are only shown when the catalog supplies real variants;
/// the player never invents quality labels for fallback URLs.
class MediaVideoSource {
  const MediaVideoSource({
    required this.url,
    required this.quality,
    this.voiceover,
  });

  final String url;
  final String quality;
  final String? voiceover;
}
