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
}
