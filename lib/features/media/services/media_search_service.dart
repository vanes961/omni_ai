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

  static const String _demoVideoUrl =
      'https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';
  static const List<String> _demoVideoFallbackUrls = [
    'https://storage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
  ];

  static const List<MediaItem> _catalog = [
    MediaItem(
      id: 'cyberpunk-edgerunners',
      title: 'Cyberpunk: Edgerunners',
      type: 'Аниме',
      posterUrl:
          'https://images.unsplash.com/photo-1519608487953-e999c86e7455?w=480&q=80',
      rating: 8.3,
      voiceovers: ['Anilibria', 'AniDUB', 'Оригинал'],
      videoUrl: _demoVideoUrl,
      videoFallbackUrls: _demoVideoFallbackUrls,
      categories: ['Аниме', 'Игры'],
      episodes: [
        MediaEpisode(number: 1, title: 'Пилот', videoUrl: _demoVideoUrl),
        MediaEpisode(number: 2, title: 'Like a Boy', videoUrl: _demoVideoUrl),
        MediaEpisode(
          number: 3,
          title: 'Smooth Criminal',
          videoUrl: _demoVideoUrl,
        ),
      ],
    ),
    MediaItem(
      id: 'interstellar',
      title: 'Интерстеллар',
      type: 'Фильм',
      posterUrl:
          'https://images.unsplash.com/photo-1446776811953-b23d57bd21aa?w=480&q=80',
      rating: 8.7,
      voiceovers: ['LostFilm', 'Оригинал'],
      videoUrl: _demoVideoUrl,
      videoFallbackUrls: _demoVideoFallbackUrls,
      categories: ['Фильмы', 'Технологии'],
    ),
    MediaItem(
      id: 'the-witcher',
      title: 'Ведьмак',
      type: 'Сериал',
      posterUrl:
          'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=480&q=80',
      rating: 8.0,
      voiceovers: ['RHS', 'LostFilm', 'Оригинал'],
      videoUrl: _demoVideoUrl,
      videoFallbackUrls: _demoVideoFallbackUrls,
      categories: ['Сериалы', 'Фэнтези'],
      episodes: [
        MediaEpisode(
          number: 1,
          title: 'The End\'s Beginning',
          videoUrl: _demoVideoUrl,
        ),
        MediaEpisode(number: 2, title: 'Four Marks', videoUrl: _demoVideoUrl),
      ],
    ),
    MediaItem(
      id: 'attack-on-titan',
      title: 'Атака Титанов',
      type: 'Аниме',
      posterUrl:
          'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=480&q=80',
      rating: 9.0,
      voiceovers: ['Anilibria', 'RHS', 'Оригинал'],
      videoUrl: _demoVideoUrl,
      videoFallbackUrls: _demoVideoFallbackUrls,
      categories: ['Аниме'],
      episodes: [
        MediaEpisode(
          number: 1,
          title: 'На тебя, спустя 2000 лет',
          videoUrl: _demoVideoUrl,
        ),
        MediaEpisode(number: 2, title: 'Тот день', videoUrl: _demoVideoUrl),
      ],
    ),
    MediaItem(
      id: 'dune',
      title: 'Дюна',
      type: 'Фильм',
      posterUrl:
          'https://images.unsplash.com/photo-1462331940025-496dfbfc7564?w=480&q=80',
      rating: 8.1,
      voiceovers: ['HDRezka', 'Оригинал'],
      videoUrl: _demoVideoUrl,
      videoFallbackUrls: _demoVideoFallbackUrls,
      categories: ['Фильмы', 'Фантастика'],
    ),
    MediaItem(
      id: 'arcane',
      title: 'Аркейн',
      type: 'Сериал',
      posterUrl:
          'https://images.unsplash.com/photo-1518837695005-2083093ee35b?w=480&q=80',
      rating: 9.1,
      voiceovers: ['RHS', 'Оригинал'],
      videoUrl: _demoVideoUrl,
      videoFallbackUrls: _demoVideoFallbackUrls,
      categories: ['Сериалы', 'Игры'],
      episodes: [
        MediaEpisode(
          number: 1,
          title: 'Welcome to the Playground',
          videoUrl: _demoVideoUrl,
        ),
        MediaEpisode(
          number: 2,
          title: 'Some Mysteries Are Better Left Unsolved',
          videoUrl: _demoVideoUrl,
        ),
      ],
    ),
  ];

  List<MediaItem> get catalog => List.unmodifiable(_catalog);

  List<MediaItem> get trending => List.unmodifiable(_catalog.take(4));

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
    final selectedCategories = preferences.categories
        .map((category) => category.trim().toLowerCase())
        .where((category) => category.isNotEmpty)
        .toSet();
    if (selectedCategories.isEmpty) return trending;

    final matching = _catalog.where((item) {
      return item.categories.any(
        (category) => selectedCategories.contains(category.toLowerCase()),
      );
    }).toList();
    matching.sort((first, second) {
      final firstFavorite = preferences.favoriteTitles.any(
        (title) => first.title.toLowerCase().contains(title.toLowerCase()),
      );
      final secondFavorite = preferences.favoriteTitles.any(
        (title) => second.title.toLowerCase().contains(title.toLowerCase()),
      );
      if (firstFavorite == secondFavorite) return 0;
      return firstFavorite ? -1 : 1;
    });
    return List.unmodifiable(matching);
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
