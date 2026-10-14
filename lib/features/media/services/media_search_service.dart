import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

class MediaSearchService {
  const MediaSearchService({this.accessToken = _token});
  static const _token = String.fromEnvironment('TMDB_ACCESS_TOKEN');
  static const tmdbAttribution =
      'This product uses the TMDB API but is not endorsed or certified by TMDB.';
  static const _api = 'https://api.themoviedb.org/3';
  static const _poster = 'https://image.tmdb.org/t/p/w500';
  final String accessToken;
  bool get isConfigured => accessToken.trim().isNotEmpty;
  static const Map<int, String> _genres = {
    28: 'Боевик',
    12: 'Приключения',
    16: 'Анимация',
    18: 'Драма',
    27: 'Ужасы',
    35: 'Комедия',
    36: 'История',
    37: 'Вестерн',
    53: 'Триллер',
    80: 'Криминал',
    99: 'Документальный',
    878: 'Фантастика',
    9648: 'Детектив',
    10402: 'Музыка',
    10749: 'Мелодрама',
    10751: 'Семейный',
    10752: 'Военный',
    10759: 'Боевик и приключения',
    10762: 'Детский',
    10765: 'Фантастика и фэнтези',
  };
  List<MediaItem> get catalog => const [];
  List<MediaItem> get trending => const [];
  List<MediaItem> search(String query, {String? type}) => const [];
  List<MediaItem> recommendedFor(UserPreferences preferences) => const [];
  Future<List<MediaItem>> searchOnline(String query, {String? type}) async {
    if (query.trim().isEmpty || !isConfigured) return const [];
    final endpoint = switch (type) {
      'Фильм' => 'movie',
      'Сериал' || 'Аниме' => 'tv',
      _ => 'multi',
    };
    final uri = Uri.parse('$_api/search/$endpoint').replace(
      queryParameters: {
        'query': query.trim(),
        'language': 'ru-RU',
        'include_adult': 'false',
        'page': '1',
      },
    );
    try {
      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer ${accessToken.trim()}',
              'accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return const [];
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic> || json['results'] is! List) {
        return const [];
      }
      final items = <MediaItem>[];
      for (final raw in json['results'] as List) {
        if (raw is! Map<String, dynamic>) continue;
        final kind = raw['media_type'] ?? endpoint;
        if (kind == 'person') continue;
        final tv = kind == 'tv';
        final lang = raw['original_language'] as String? ?? '';
        final countries = (raw['origin_country'] as List? ?? const [])
            .whereType<String>();
        final anime = tv && (lang == 'ja' || countries.contains('JP'));
        if ((type == 'Аниме' && !anime) || (type == 'Сериал' && anime)) {
          continue;
        }
        final title = (raw[tv ? 'name' : 'title'] as String? ?? '').trim();
        final id = raw['id'];
        if (title.isEmpty || id == null) continue;
        final poster = raw['poster_path'] as String?;
        final ids = (raw['genre_ids'] as List? ?? const []).whereType<num>();
        items.add(
          MediaItem(
            id: 'tmdb:${tv ? 'tv' : 'movie'}:$id',
            title: title,
            type: anime
                ? 'Аниме'
                : tv
                ? 'Сериал'
                : 'Фильм',
            posterUrl: poster == null ? '' : '$_poster$poster',
            rating: (raw['vote_average'] as num?)?.toDouble() ?? 0,
            voiceovers: const [],
            videoUrl: '',
            categories: ids
                .map((g) => _genres[g.toInt()])
                .whereType<String>()
                .toList(),
            description: raw['overview'] as String? ?? '',
          ),
        );
      }
      return items;
    } on Object {
      return const [];
    }
  }

  Future<MediaDetails?> loadDetails(MediaItem item) async {
    if (!isConfigured || !item.id.startsWith('tmdb:')) return null;
    final p = item.id.split(':');
    if (p.length != 3 || !{'movie', 'tv'}.contains(p[1])) return null;
    final uri = Uri.parse('$_api/${p[1]}/${p[2]}').replace(
      queryParameters: {'language': 'ru-RU', 'append_to_response': 'credits'},
    );
    try {
      final r = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer ${accessToken.trim()}',
              'accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final data = jsonDecode(r.body);
      if (data is! Map<String, dynamic>) return null;
      final credits = data['credits'] as Map<String, dynamic>? ?? const {};
      final cast = (credits['cast'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .take(12)
          .map(
            (x) => MediaCastMember(
              name: x['name'] as String? ?? '',
              character: x['character'] as String? ?? '',
              photoUrl: x['profile_path'] is String
                  ? 'https://image.tmdb.org/t/p/w185${x['profile_path']}'
                  : '',
            ),
          )
          .where((x) => x.name.isNotEmpty)
          .toList();
      final genres = (data['genres'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((x) => x['name'])
          .whereType<String>()
          .toList();
      int? runtime;
      if (data['runtime'] is num) {
        runtime = (data['runtime'] as num).toInt();
      } else {
        for (final x in (data['episode_run_time'] as List? ?? const [])) {
          if (x is num) {
            runtime = x.toInt();
            break;
          }
        }
      }
      final seasons = parseCatalogSeasons(data['seasons']);
      final b = data['backdrop_path'] as String?;
      return MediaDetails(
        overview: data['overview'] as String? ?? item.description,
        genres: genres.isEmpty ? item.categories : genres,
        cast: cast,
        runtimeMinutes: runtime,
        releaseDate:
            data['release_date'] as String? ??
            data['first_air_date'] as String? ??
            '',
        backdropUrl: b == null ? '' : 'https://image.tmdb.org/t/p/w1280$b',
        homepage: data['homepage'] as String? ?? '',
        seasons: seasons,
      );
    } on Object {
      return null;
    }
  }

  /// Loads episode metadata for a TMDB TV season. These entries deliberately
  /// contain no playable URLs; a stream resolver must supply real sources.
  Future<List<MediaCatalogEpisode>> loadSeasonEpisodes(
    MediaItem item,
    int seasonNumber,
  ) async {
    if (!isConfigured || !item.id.startsWith('tmdb:tv:') || seasonNumber < 0) {
      return const [];
    }
    final parts = item.id.split(':');
    if (parts.length != 3 || int.tryParse(parts[2]) == null) {
      return const [];
    }
    final uri = Uri.parse(
      '$_api/tv/${parts[2]}/season/$seasonNumber',
    ).replace(queryParameters: {'language': 'ru-RU'});
    try {
      final response = await http
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer ${accessToken.trim()}',
              'accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return const [];
      return parseSeasonEpisodes(
        jsonDecode(response.body),
        seasonNumber: seasonNumber,
      );
    } on Object {
      return const [];
    }
  }

  /// Parses season summaries returned by TMDB series details.
  static List<MediaCatalogSeason> parseCatalogSeasons(Object? payload) {
    if (payload is! List) return const [];
    final seasons = <MediaCatalogSeason>[];
    for (final raw in payload) {
      if (raw is! Map<String, dynamic>) continue;
      final number = raw['season_number'];
      final name = (raw['name'] as String? ?? '').trim();
      if (number is! num || number < 0 || name.isEmpty) continue;
      seasons.add(
        MediaCatalogSeason(
          seasonNumber: number.toInt(),
          name: name,
          episodeCount: (raw['episode_count'] as num?)?.toInt() ?? 0,
          airDate: raw['air_date'] as String? ?? '',
          overview: raw['overview'] as String? ?? '',
        ),
      );
    }
    seasons.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    return seasons;
  }

  /// Parses catalog-only episode metadata without inventing stream URLs.
  static List<MediaCatalogEpisode> parseSeasonEpisodes(
    Object? payload, {
    required int seasonNumber,
  }) {
    if (payload is! Map<String, dynamic> || payload['episodes'] is! List) {
      return const [];
    }
    final episodes = <MediaCatalogEpisode>[];
    for (final raw in payload['episodes'] as List) {
      if (raw is! Map<String, dynamic>) continue;
      final number = raw['episode_number'];
      final title = (raw['name'] as String? ?? '').trim();
      if (number is! num || number <= 0 || title.isEmpty) continue;
      final still = raw['still_path'] as String?;
      episodes.add(
        MediaCatalogEpisode(
          seasonNumber: seasonNumber,
          episodeNumber: number.toInt(),
          title: title,
          overview: raw['overview'] as String? ?? '',
          airDate: raw['air_date'] as String? ?? '',
          stillUrl: still == null
              ? ''
              : 'https://image.tmdb.org/t/p/w500$still',
        ),
      );
    }
    episodes.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    return episodes;
  }

  String? preferredVoiceover(MediaItem item, UserPreferences preferences) {
    for (final p in preferences.voiceDubbing) {
      for (final v in item.voiceovers) {
        if (v.toLowerCase() == p.trim().toLowerCase()) return v;
      }
    }
    return item.voiceovers.isEmpty ? null : item.voiceovers.first;
  }
}

class MediaCatalogSeason {
  const MediaCatalogSeason({
    required this.seasonNumber,
    required this.name,
    required this.episodeCount,
    required this.airDate,
    required this.overview,
  });

  final int seasonNumber;
  final String name;
  final int episodeCount;
  final String airDate;
  final String overview;
}

class MediaDetails {
  const MediaDetails({
    required this.overview,
    required this.genres,
    required this.cast,
    required this.runtimeMinutes,
    required this.releaseDate,
    required this.backdropUrl,
    required this.homepage,
    this.seasons = const [],
  });
  final String overview;
  final List<String> genres;
  final List<MediaCastMember> cast;
  final int? runtimeMinutes;
  final String releaseDate, backdropUrl, homepage;
  final List<MediaCatalogSeason> seasons;
}

/// Descriptive season metadata from a catalog; intentionally not playable.
class MediaCatalogEpisode {
  const MediaCatalogEpisode({
    required this.seasonNumber,
    required this.episodeNumber,
    required this.title,
    required this.overview,
    required this.airDate,
    required this.stillUrl,
  });

  final int seasonNumber;
  final int episodeNumber;
  final String title;
  final String overview;
  final String airDate;
  final String stillUrl;
}

class MediaCastMember {
  const MediaCastMember({
    required this.name,
    required this.character,
    required this.photoUrl,
  });
  final String name, character, photoUrl;
}
