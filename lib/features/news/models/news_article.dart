enum NewsContentType {
  article,
  video,
  trailer;

  static NewsContentType fromJson(Object? value) {
    return switch (value) {
      'video' => NewsContentType.video,
      'trailer' => NewsContentType.trailer,
      _ => NewsContentType.article,
    };
  }
}

class NewsArticle {
  const NewsArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.sourceName,
    required this.sourceUrl,
    required this.publishedAt,
    required this.topics,
    this.language = 'ru',
    this.region,
    this.isCritical = false,
    this.isVerified = false,
    this.contentType = NewsContentType.article,
    this.videoUrl,
    this.thumbnailUrl,
    this.channelName,
    this.releaseDate,
    this.releaseDateSourceUrl,
  });

  final String id;
  final String title;
  final String summary;
  final String sourceName;
  final String sourceUrl;
  final DateTime publishedAt;
  final List<String> topics;
  final String language;
  final String? region;
  final bool isCritical;
  final bool isVerified;

  /// Text articles remain the default for old RSS and cached records.
  final NewsContentType contentType;

  /// Original watch URL and thumbnail supplied by a video metadata provider.
  final String? videoUrl;
  final String? thumbnailUrl;
  final String? channelName;

  /// Release dates must come with a source; unknown dates stay null.
  final DateTime? releaseDate;
  final String? releaseDateSourceUrl;
}
