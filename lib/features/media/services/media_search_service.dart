import 'dart:convert';

import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/core/network/network_service.dart';

class MediaSearchService {
  const MediaSearchService({
    this.networkService = const NetworkService(),
    this.apiKey = const String.fromEnvironment('KINOPOISK_API_KEY'),
  });

  final NetworkService networkService;
  final String apiKey;

  static const _searchEndpoint =
      'https://kinopoiskapiunofficial.tech/api/v2.1/films/search-by-keyword';

  // No fabricated catalog, sample video streams or hard-coded dubbing providers.
  // Media entries are populated only from the configured online catalog.
  static const List<MediaItem> _catalog = <MediaItem>[];

  List<MediaItem> get catalog => List.unmodifiable(_catalog);

  List<MediaItem> get trending => List.unmodifiable(_catalog);

  Future<List<MediaItem>> searchOnline(String query) async {
    final keyword = query.trim();
    if (apiKey.isEmpty || keyword.length < 2) return const [];

    final response = await networkService.get(
      Uri.parse(
        _searchEndpoint,
      ).replace(queryParameters: {'keyword': keyword, 'page': '1'}),
      headers: {'X-API-KEY': apiKey, 'Accept': 'application/json'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) return const [];
    final films = payload['searchFilms'];
    if (films is! List) return const [];

    return films.whereType<Map<String, dynamic>>().map(_toMediaItem).toList();
  }

  MediaItem _toMediaItem(Map<String, dynamic> film) {
    final id = film['filmId']?.toString() ?? film['kinopoiskId']?.toString();
    final russianTitle = film['nameRu'] as String? ?? '';
    final englishTitle = film['nameEn'] as String? ?? '';
    final title = russianTitle.trim().isNotEmpty
        ? russianTitle.trim()
        : englishTitle.trim();
    final rawRating = film['rating']?.toString() ?? '';
    final rawGenres = film['genres'];
    final genres = rawGenres is List
        ? rawGenres
              .whereType<Map<String, dynamic>>()
              .map((genre) => genre['genre']?.toString() ?? '')
              .where((genre) => genre.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final rawType = (film['type'] as String? ?? '').toUpperCase();
    final type = switch (rawType) {
      'TV_SERIES' || 'TV_SHOW' || 'MINI_SERIES' => 'Сериал',
      'FILM' => 'Фильм',
      _ => rawType.contains('ANIME') ? 'Аниме' : 'Фильм',
    };

    return MediaItem(
      id: 'kinopoisk-${id ?? title.hashCode}',
      title: title.isEmpty ? 'Без названия' : title,
      type: type,
      posterUrl: film['posterUrl'] as String? ?? '',
      rating: double.tryParse(rawRating.replaceAll(',', '.')) ?? 0,
      voiceovers: const [],
      videoUrl: '',
      categories: genres,
      description: film['description'] as String? ?? '',
    );
  }

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
    // Recommendations require real catalog metadata; never show demo titles.
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
