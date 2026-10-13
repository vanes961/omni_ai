import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

class MediaSearchService {
  const MediaSearchService();

  /// ZONA's public web catalog is opened externally; no undocumented API,
  /// scraped stream URLs, or embedded third-party API keys are used.
  static final Uri zonaCatalogUri = Uri.parse('https://w1.zona.im/');

  static const List<MediaItem> _catalog = <MediaItem>[];

  List<MediaItem> get catalog => List.unmodifiable(_catalog);

  List<MediaItem> get trending => List.unmodifiable(_catalog);

  List<MediaItem> search(String query, {String? type}) {
    final normalizedQuery = query.trim().toLowerCase();
    return _catalog
        .where((item) {
          final matchesType = type == null || item.type == type;
          final matchesQuery =
              normalizedQuery.isEmpty ||
              item.title.toLowerCase().contains(normalizedQuery) ||
              item.type.toLowerCase().contains(normalizedQuery) ||
              item.categories.any(
                (category) => category.toLowerCase().contains(normalizedQuery),
              ) ||
              item.voiceovers.any(
                (voiceover) =>
                    voiceover.toLowerCase().contains(normalizedQuery),
              );
          return matchesType && matchesQuery;
        })
        .toList(growable: false);
  }

  List<MediaItem> recommendedFor(UserPreferences preferences) {
    // Recommendations require real metadata; never show fabricated titles.
    return const <MediaItem>[];
  }

  String? preferredVoiceover(MediaItem item, UserPreferences preferences) {
    for (final preferred in preferences.voiceDubbing) {
      for (final available in item.voiceovers) {
        if (available.toLowerCase() == preferred.trim().toLowerCase()) {
          return available;
        }
      }
    }
    return item.voiceovers.isEmpty ? null : item.voiceovers.first;
  }
}
