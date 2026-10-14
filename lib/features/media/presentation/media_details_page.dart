import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/domain/media_hub_contracts.dart';
import 'package:omni_ai/features/media/presentation/player_page.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class MediaDetailsPage extends StatelessWidget {
  const MediaDetailsPage({
    required this.item,
    required this.searchService,
    required this.preferences,
    this.playerFactory,
    super.key,
  });
  final MediaItem item;
  final MediaSearchService searchService;
  final UserPreferences preferences;
  final MediaPlayerFactory? playerFactory;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: SystemCorePalette.background,
    appBar: AppBar(
      title: const Text('О ФИЛЬМЕ'),
      backgroundColor: SystemCorePalette.panel,
    ),
    body: FutureBuilder<MediaDetails?>(
      future: searchService.loadDetails(item),
      builder: (context, s) {
        final d = s.data;
        final overview = d?.overview.isNotEmpty == true
            ? d!.overview
            : item.description;
        final genres = d?.genres ?? item.categories;
        return ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (d?.backdropUrl.isNotEmpty == true)
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  d!.backdropUrl,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.posterUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      item.posterUrl,
                      width: 112,
                      height: 166,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.type,
                        style: const TextStyle(color: SystemCorePalette.muted),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '★ ${item.rating.toStringAsFixed(1)}',
                        style: const TextStyle(
                          color: SystemCorePalette.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (d?.releaseDate.isNotEmpty == true)
                        Text(
                          d!.releaseDate,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      if (d?.runtimeMinutes != null)
                        Text(
                          '${d!.runtimeMinutes} мин.',
                          style: const TextStyle(color: Colors.white70),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const _Label('ОПИСАНИЕ'),
            const SizedBox(height: 8),
            Text(
              overview.isEmpty ? 'Описание пока недоступно.' : overview,
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
            const SizedBox(height: 20),
            const _Label('ЖАНРЫ'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: genres
                  .map(
                    (g) => Chip(
                      label: Text(g),
                      backgroundColor: SystemCorePalette.panel,
                      labelStyle: const TextStyle(color: Colors.white),
                      side: BorderSide(
                        color: SystemCorePalette.green.withValues(alpha: .4),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            const _Label('АКТЁРСКИЙ СОСТАВ'),
            const SizedBox(height: 8),
            if (s.connectionState == ConnectionState.waiting && d == null)
              const Center(child: CircularProgressIndicator()),
            if (d != null)
              SizedBox(
                height: 170,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: d.cast.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final a = d.cast[i];
                    return SizedBox(
                      width: 100,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (a.photoUrl.isEmpty)
                            Container(
                              width: 100,
                              height: 110,
                              color: SystemCorePalette.panel,
                              child: const Icon(
                                Icons.person,
                                color: SystemCorePalette.muted,
                              ),
                            )
                          else
                            Image.network(
                              a.photoUrl,
                              width: 100,
                              height: 110,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 100,
                                height: 110,
                                color: SystemCorePalette.panel,
                                child: const Icon(
                                  Icons.person,
                                  color: SystemCorePalette.muted,
                                ),
                              ),
                            ),
                          const SizedBox(height: 5),
                          Text(
                            a.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            a.character,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SystemCorePalette.muted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            if (d != null && d.cast.isEmpty)
              const Text(
                'Информация об актёрах недоступна.',
                style: TextStyle(color: Colors.white70),
              ),
            if ((item.type == 'Сериал' || item.type == 'Аниме') &&
                d?.seasons.isNotEmpty == true) ...[
              const SizedBox(height: 20),
              const _Label('СЕЗОНЫ И СЕРИИ'),
              const SizedBox(height: 8),
              ...d!.seasons.map(
                (season) => _SeasonCatalogSection(
                  item: item,
                  season: season,
                  searchService: searchService,
                  preferences: preferences,
                  playerFactory: playerFactory,
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (item.videoUrl.isNotEmpty)
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlayerPage(
                      item: item,
                      preferences: preferences,
                      searchService: searchService,
                      playerFactory: playerFactory,
                    ),
                  ),
                ),
                icon: const Icon(Icons.play_arrow),
                label: const Text('СМОТРЕТЬ'),
              ),
            OutlinedButton.icon(
              key: const ValueKey('choose-media-source'),
              onPressed: () => _chooseAndPlaySource(
                context,
                item,
                preferences,
                searchService,
                playerFactory,
              ),
              icon: const Icon(Icons.link),
              label: const Text('УКАЗАТЬ ИСТОЧНИК ВИДЕО'),
            ),
            if (d?.homepage.isNotEmpty == true)
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(d!.homepage),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('ОФИЦИАЛЬНАЯ СТРАНИЦА'),
              ),
            const SizedBox(height: 12),
            const Text(
              'This product uses the TMDB API but is not endorsed or certified by TMDB.',
              style: TextStyle(color: SystemCorePalette.muted, fontSize: 10),
            ),
          ],
        );
      },
    ),
  );
}

class _SeasonCatalogSection extends StatefulWidget {
  const _SeasonCatalogSection({
    required this.item,
    required this.season,
    required this.searchService,
    required this.preferences,
    required this.playerFactory,
  });

  final MediaItem item;
  final MediaCatalogSeason season;
  final MediaSearchService searchService;
  final UserPreferences preferences;
  final MediaPlayerFactory? playerFactory;

  @override
  State<_SeasonCatalogSection> createState() => _SeasonCatalogSectionState();
}

class _SeasonCatalogSectionState extends State<_SeasonCatalogSection> {
  Future<List<MediaCatalogEpisode>>? _episodesFuture;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: PageStorageKey(
      'season-${widget.item.id}-${widget.season.seasonNumber}',
    ),
    title: Text(
      widget.season.name,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      '${widget.season.episodeCount} серий'
      '${widget.season.airDate.isEmpty ? '' : ' • ${widget.season.airDate}'}',
      style: const TextStyle(color: SystemCorePalette.muted),
    ),
    iconColor: SystemCorePalette.green,
    collapsedIconColor: SystemCorePalette.muted,
    onExpansionChanged: (expanded) {
      setState(() {
        _expanded = expanded;
        if (expanded && _episodesFuture == null) {
          _episodesFuture = widget.searchService.loadSeasonEpisodes(
            widget.item,
            widget.season.seasonNumber,
          );
        }
      });
    },
    children: [
      if (_expanded)
        FutureBuilder<List<MediaCatalogEpisode>>(
          future: _episodesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final episodes = snapshot.data ?? const <MediaCatalogEpisode>[];
            if (episodes.isEmpty) {
              return const ListTile(
                title: Text(
                  'Список серий пока недоступен',
                  style: TextStyle(color: SystemCorePalette.muted),
                ),
              );
            }
            return Column(
              children: episodes
                  .map(
                    (episode) => ListTile(
                      key: ValueKey(
                        'episode-source-${widget.item.id}-'
                        '${widget.season.seasonNumber}-${episode.episodeNumber}',
                      ),
                      onTap: () => _chooseAndPlaySource(
                        context,
                        widget.item,
                        widget.preferences,
                        widget.searchService,
                        widget.playerFactory,
                        episode: episode,
                      ),
                      dense: true,
                      leading: Text(
                        episode.episodeNumber.toString().padLeft(2, '0'),
                        style: const TextStyle(color: SystemCorePalette.green),
                      ),
                      title: Text(
                        episode.title,
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: const Icon(
                        Icons.play_circle_outline,
                        color: SystemCorePalette.green,
                        size: 20,
                      ),
                      subtitle: episode.overview.isEmpty
                          ? null
                          : Text(
                              episode.overview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: SystemCorePalette.muted,
                              ),
                            ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
    ],
  );
}

Future<void> _chooseAndPlaySource(
  BuildContext context,
  MediaItem item,
  UserPreferences preferences,
  MediaSearchService searchService,
  MediaPlayerFactory? playerFactory, {
  MediaCatalogEpisode? episode,
}) async {
  final controller = TextEditingController();
  final raw = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: SystemCorePalette.panel,
      title: Text(
        episode == null
            ? 'Источник видео'
            : 'Источник серии ${episode.episodeNumber}',
        style: const TextStyle(color: Colors.white),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'https://… или magnet:?xt=urn:btih:…',
          hintStyle: TextStyle(color: SystemCorePalette.muted),
          helperText:
              'Вставьте ссылку на доступный вам видеоисточник или magnet-ссылку.',
          helperMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('ОТМЕНА'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: const Text('ОТКРЫТЬ'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (!context.mounted || raw == null || raw.isEmpty) return;

  final uri = Uri.tryParse(raw);
  final source = uri == null
      ? null
      : MediaStreamSource(
          id: 'user-supplied',
          label: 'Пользовательский источник',
          uri: uri,
        );
  if (source == null || !source.isSupportedInput) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Нужна корректная HTTP(S)-ссылка или magnet-ссылка '
          'с BitTorrent hash.',
        ),
      ),
    );
    return;
  }

  final playableItem = MediaItem(
    id: item.id,
    title: item.title,
    type: item.type,
    posterUrl: item.posterUrl,
    posterFallbackUrls: item.posterFallbackUrls,
    rating: item.rating,
    // The user explicitly selected this URL, so stale catalog variants,
    // voiceover URLs, and fallbacks must not override it in the player.
    voiceovers: const [],
    videoUrl: uri.toString(),
    videoFallbackUrls: const [],
    voiceoverVideoUrls: const {},
    categories: item.categories,
    description: item.description,
    malId: item.malId,
    videoSources: const [],
    episodes: episode == null
        ? const []
        : [
            MediaEpisode(
              number: episode.episodeNumber,
              seasonNumber: episode.seasonNumber,
              title: episode.title,
              videoUrl: uri.toString(),
            ),
          ],
  );

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlayerPage(
        item: playableItem,
        preferences: preferences,
        searchService: searchService,
        playerFactory: playerFactory,
      ),
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.value);
  final String value;
  @override
  Widget build(BuildContext context) => Text(
    value,
    style: const TextStyle(
      color: SystemCorePalette.green,
      fontSize: 11,
      letterSpacing: 1,
      fontWeight: FontWeight.bold,
    ),
  );
}
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
              'Authorization': '***',
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
              'Authorization': '***',
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
              'Authorization': '***',
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
