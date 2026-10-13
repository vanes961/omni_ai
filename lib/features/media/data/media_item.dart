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
}

class MediaEpisode {
  const MediaEpisode({
    required this.number,
    required this.title,
    required this.videoUrl,
    this.videoFallbackUrls = const [],
    this.voiceoverVideoUrls = const {},
  });

  final int number;
  final String title;
  final String videoUrl;
  final List<String> videoFallbackUrls;
  final Map<String, String> voiceoverVideoUrls;

  String get label => 'СЕРИЯ ${number.toString().padLeft(2, '0')}  //  $title';
}
