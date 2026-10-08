class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.type,
    required this.posterUrl,
    required this.rating,
    required this.voiceovers,
    required this.videoUrl,
    this.categories = const [],
    this.episodes = const [],
  });

  final String id;
  final String title;
  final String type;
  final String posterUrl;
  final double rating;
  final List<String> voiceovers;
  final String videoUrl;
  final List<String> categories;
  final List<MediaEpisode> episodes;
}

class MediaEpisode {
  const MediaEpisode({
    required this.number,
    required this.title,
    required this.videoUrl,
  });

  final int number;
  final String title;
  final String videoUrl;

  String get label => 'СЕРИЯ ${number.toString().padLeft(2, '0')}  //  $title';
}
