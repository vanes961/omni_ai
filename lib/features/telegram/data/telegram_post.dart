class TelegramPost {
  const TelegramPost({
    required this.id,
    required this.channelName,
    required this.text,
    required this.timestamp,
    required this.isPinned,
    this.mediaUrl,
    this.sourceUrl,
  });

  final String id;
  final String channelName;
  final String text;
  final String? mediaUrl;
  final DateTime timestamp;
  final bool isPinned;
  final String? sourceUrl;
}
