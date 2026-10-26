import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/sources/anilibria_catalog_source.dart';
import 'package:omni_ai/features/media/sources/media_source.dart';
import 'package:omni_ai/features/media/sources/media_source_engine.dart';
import 'package:omni_ai/features/media/sources/kinopoisk_catalog_source.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

typedef FranchiseChronologyResolver =
    Future<List<MediaFranchiseEntry>> Function({
      required String franchiseId,
      required List<MediaFranchiseEntry> entries,
    });

class MediaSearchService {
  const MediaSearchService({
    this.accessToken = _token,
    this.kinopoiskApiKey = _kinopoiskToken,
    this.franchiseChronologyResolver,
    this.client,
    this.sourceEngine,
  });

  static const _kinopoiskToken = String.fromEnvironment('POISKKINO_API_KEY');
  static const _token = String.fromEnvironment('TMDB_ACCESS_TOKEN');
  final http.Client? client;
  final MediaSourceEngine? sourceEngine;

  /// Can be supplied from secure device storage at runtime. The build-time
  /// define remains a fallback for development builds only.
  final String kinopoiskApiKey;

  MediaSourceEngine get _mediaSources =>
      sourceEngine ??
      MediaSourceEngine([
        AniLibriaCatalogSource(client: client),
        KinopoiskCatalogSource(apiKey: kinopoiskApiKey, client: client),
      ]);

  /// Keeps the same HTTP transport while replacing the credential loaded from
  /// secure device storage. This makes runtime credentials testable and avoids
  /// silently losing an injected client when the page loads its token.
  MediaSearchService withAccessToken(String token) => MediaSearchService(
    accessToken: token,
    kinopoiskApiKey: kinopoiskApiKey,
    franchiseChronologyResolver: franchiseChronologyResolver,
    client: client,
    sourceEngine: sourceEngine,
  );

  /// Rebuilds the default catalog engine with a runtime PoiskKino key.
  /// An explicitly injected source engine is preserved for tests/custom setups.
  MediaSearchService withKinopoiskApiKey(String key) => MediaSearchService(
    accessToken: accessToken,
    kinopoiskApiKey: key.trim(),
    franchiseChronologyResolver: franchiseChronologyResolver,
    client: client,
    sourceEngine:
        sourceEngine ??
        MediaSourceEngine([
          AniLibriaCatalogSource(),
          KinopoiskCatalogSource(apiKey: key.trim()),
        ]),
  );

  Future<http.Response> _get(Uri uri, {required Map<String, String> headers}) {
    final transport = client;
    return transport == null
        ? http.get(uri, headers: headers)
        : transport.get(uri, headers: headers);
  }

  static const tmdbAttribution =
      'This product uses the TMDB API but is not endorsed or certified by TMDB.';
  static const _api = 'https://api.themoviedb.org/3';
  static const _poster = 'https://image.tmdb.org/t/p/w500';
  final String accessToken;
  final FranchiseChronologyResolver? franchiseChronologyResolver;
  bool get isConfigured => accessToken.trim().isNotEmpty;
  bool get isSearchConfigured =>
      isConfigured || kinopoiskApiKey.trim().isNotEmpty;
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
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return const [];

    // AniLibria is an independent anime catalog, so anime search remains
    // useful when the optional TMDB token is missing or temporarily offline.
    if (type == 'Аниме' && !isConfigured) {
      return _searchAnimeCatalog(normalizedQuery);
    }

    // Prefer the user-configured PoiskKino catalog for films and series. TMDB
    // remains a fallback for missing credentials, empty results, or outages.
    final supportsPoiskKino = type == 'Фильм' || type == 'Сериал';
    if (supportsPoiskKino && kinopoiskApiKey.trim().isNotEmpty) {
      final catalogItems = await _searchCatalogFallback(normalizedQuery, type);
      if (catalogItems.isNotEmpty || !isConfigured) return catalogItems;
    }
    if (!isConfigured) {
      return _searchCatalogFallback(normalizedQuery, type);
    }

    final endpoint = switch (type) {
      'Фильм' => 'movie',
      'Сериал' || 'Аниме' => 'tv',
      _ => 'multi',
    };
    final uri = Uri.parse('$_api/search/$endpoint').replace(
      queryParameters: {
        'query': normalizedQuery,
        'language': 'ru-RU',
        'include_adult': 'false',
        'page': '1',
      },
    );
    try {
      final response = await _get(
        uri,
        headers: {
          'Authorization': '***',
          'accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        return type == 'Аниме'
            ? await _searchAnimeCatalog(normalizedQuery)
            : await _searchCatalogFallback(normalizedQuery, type);
      }
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic> || json['results'] is! List) {
        return type == 'Аниме'
            ? await _searchAnimeCatalog(normalizedQuery)
            : await _searchCatalogFallback(normalizedQuery, type);
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
      if (type == 'Аниме' && items.isEmpty) {
        return await _searchAnimeCatalog(normalizedQuery);
      }
      if (items.isEmpty) {
        return await _searchCatalogFallback(normalizedQuery, type);
      }
      return items;
    } on Object {
      return type == 'Аниме'
          ? await _searchAnimeCatalog(normalizedQuery)
          : await _searchCatalogFallback(normalizedQuery, type);
    }
  }

  Future<List<MediaItem>> _searchCatalogFallback(String query, String? type) {
    final kind = switch (type) {
      'Фильм' => MediaSourceKind.movie,
      'Сериал' => MediaSourceKind.series,
      _ => null,
    };
    if (kind == null) return Future.value(const <MediaItem>[]);
    return _mediaSources.search(query, kind: kind);
  }

  Future<List<MediaItem>> _searchAnimeCatalog(String query) =>
      _mediaSources.search(query, kind: MediaSourceKind.anime);

  /// Loads real weekly trending titles from TMDB for the media hub.
  /// Returns an empty list when credentials or the network are unavailable;
  /// no demo titles are substituted.
  Future<List<MediaItem>> fetchTrendingOnline({String? type}) async {
    if (!isConfigured) return _fetchPoiskKinoDiscovery(type);
    final mediaType = switch (type) {
      'Фильм' => 'movie',
      'Сериал' || 'Аниме' => 'tv',
      _ => 'all',
    };
    final uri = Uri.parse(
      '$_api/trending/$mediaType/week',
    ).replace(queryParameters: {'language': 'ru-RU'});
    try {
      final response = await _get(
        uri,
        headers: {
          'Authorization': '***',
          'accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        return await _fetchPoiskKinoDiscovery(type);
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['results'] is! List) {
        return await _fetchPoiskKinoDiscovery(type);
      }
      final items = <MediaItem>[];
      for (final raw in decoded['results'] as List) {
        if (raw is! Map<String, dynamic>) continue;
        final kind = raw['media_type'] as String? ?? mediaType;
        if (kind != 'movie' && kind != 'tv') continue;
        final originalLanguage = raw['original_language'] as String? ?? '';
        final countries = (raw['origin_country'] as List? ?? const [])
            .whereType<String>();
        final isAnime =
            kind == 'tv' &&
            (originalLanguage == 'ja' || countries.contains('JP'));
        if (type == 'Фильм' && kind != 'movie' ||
            type == 'Сериал' && (kind != 'tv' || isAnime) ||
            type == 'Аниме' && !isAnime) {
          continue;
        }
        final title = (raw[kind == 'tv' ? 'name' : 'title'] as String? ?? '')
            .trim();
        final id = raw['id'];
        if (title.isEmpty || id is! num) continue;
        final poster = raw['poster_path'] as String?;
        final genreIds = (raw['genre_ids'] as List? ?? const [])
            .whereType<num>();
        items.add(
          MediaItem(
            id: 'tmdb:$kind:${id.toInt()}',
            title: title,
            type: isAnime
                ? 'Аниме'
                : kind == 'tv'
                ? 'Сериал'
                : 'Фильм',
            posterUrl: poster == null ? '' : '$_poster$poster',
            rating: (raw['vote_average'] as num?)?.toDouble() ?? 0,
            voiceovers: const [],
            videoUrl: '',
            categories: genreIds
                .map((genre) => _genres[genre.toInt()])
                .whereType<String>()
                .toList(),
            description: raw['overview'] as String? ?? '',
          ),
        );
      }
      return items.isEmpty ? await _fetchPoiskKinoDiscovery(type) : items;
    } on Object {
      return _fetchPoiskKinoDiscovery(type);
    }
  }

  Future<List<MediaItem>> _fetchPoiskKinoDiscovery(String? type) async {
    if (kinopoiskApiKey.trim().isEmpty || type == 'Аниме') {
      return const [];
    }
    final source = KinopoiskCatalogSource(
      apiKey: kinopoiskApiKey,
      client: client,
    );
    try {
      if (type == 'Фильм') {
        return await source.fetchPopular(kind: MediaSourceKind.movie);
      }
      if (type == 'Сериал') {
        return await source.fetchPopular(kind: MediaSourceKind.series);
      }
      final results = await Future.wait([
        source.fetchPopular(kind: MediaSourceKind.movie),
        source.fetchPopular(kind: MediaSourceKind.series),
      ]);
      final unique = <String, MediaItem>{};
      for (final item in results.expand((items) => items)) {
        unique.putIfAbsent(item.id, () => item);
      }
      return List<MediaItem>.unmodifiable(unique.values);
    } on Object {
      return const [];
    }
  }

  /// Builds a real recommendation pool from genres saved with favorites.
  /// Empty or unrecognized interests do not trigger generic/demo suggestions.
  Future<List<MediaItem>> fetchRecommendationsOnline({
    required List<String> interests,
    String? type,
  }) async {
    if (interests.isEmpty) return const [];
    if (!isConfigured) {
      return _fetchPoiskKinoRecommendations(interests: interests, type: type);
    }

    final normalizedInterests = interests
        .map((interest) => interest.trim().toLowerCase())
        .where((interest) => interest.isNotEmpty)
        .toSet();
    final genreIds = _genres.entries
        .where(
          (entry) => normalizedInterests.contains(entry.value.toLowerCase()),
        )
        .map((entry) => entry.key)
        .toList();
    if (genreIds.isEmpty) {
      return _fetchPoiskKinoRecommendations(interests: interests, type: type);
    }

    final mediaTypes = switch (type) {
      'Фильм' => const ['movie'],
      'Сериал' || 'Аниме' => const ['tv'],
      _ => const ['movie', 'tv'],
    };
    final responses = await Future.wait(
      mediaTypes.map((mediaType) async {
        final uri = Uri.parse('$_api/discover/$mediaType').replace(
          queryParameters: {
            'language': 'ru-RU',
            'sort_by': 'popularity.desc',
            'include_adult': 'false',
            'page': '1',
            'with_genres': genreIds.join(','),
          },
        );
        try {
          final response = await _get(
            uri,
            headers: {
              'Authorization': '***',
              'accept': 'application/json',
            },
          ).timeout(const Duration(seconds: 12));
          if (response.statusCode != 200) return const <MediaItem>[];
          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic> || decoded['results'] is! List) {
            return const <MediaItem>[];
          }
          final items = <MediaItem>[];
          for (final raw in decoded['results'] as List) {
            if (raw is! Map<String, dynamic>) continue;
            final isTv = mediaType == 'tv';
            final originalLanguage = raw['original_language'] as String? ?? '';
            final countries = (raw['origin_country'] as List? ?? const [])
                .whereType<String>();
            final isAnime =
                isTv && (originalLanguage == 'ja' || countries.contains('JP'));
            if (type == 'Аниме' && !isAnime || type == 'Сериал' && isAnime) {
              continue;
            }
            final title = (raw[isTv ? 'name' : 'title'] as String? ?? '')
                .trim();
            final id = raw['id'];
            if (title.isEmpty || id is! num) continue;
            final poster = raw['poster_path'] as String?;
            final ids = (raw['genre_ids'] as List? ?? const [])
                .whereType<num>();
            items.add(
              MediaItem(
                id: 'tmdb:$mediaType:${id.toInt()}',
                title: title,
                type: isAnime
                    ? 'Аниме'
                    : isTv
                    ? 'Сериал'
                    : 'Фильм',
                posterUrl: poster == null ? '' : '$_poster$poster',
                rating: (raw['vote_average'] as num?)?.toDouble() ?? 0,
                voiceovers: const [],
                videoUrl: '',
                categories: ids
                    .map((genre) => _genres[genre.toInt()])
                    .whereType<String>()
                    .toList(),
                description: raw['overview'] as String? ?? '',
              ),
            );
          }
          return items;
        } on Object {
          return const <MediaItem>[];
        }
      }),
    );

    final unique = <String, MediaItem>{};
    for (final item in responses.expand((items) => items)) {
      unique.putIfAbsent(item.id, () => item);
    }
    if (unique.isEmpty) {
      return _fetchPoiskKinoRecommendations(interests: interests, type: type);
    }
    return List<MediaItem>.unmodifiable(unique.values);
  }

  Future<List<MediaItem>> _fetchPoiskKinoRecommendations({
    required List<String> interests,
    String? type,
  }) async {
    if (kinopoiskApiKey.trim().isEmpty || type == 'Аниме') {
      return const [];
    }
    const genreAliases = <String, String>{
      'боевик': 'боевик',
      'приключения': 'приключения',
      'анимация': 'мультфильм',
      'драма': 'драма',
      'ужасы': 'ужасы',
      'комедия': 'комедия',
      'история': 'история',
      'вестерн': 'вестерн',
      'триллер': 'триллер',
      'криминал': 'криминал',
      'документальный': 'документальный',
      'фантастика': 'фантастика',
      'детектив': 'детектив',
      'музыка': 'музыка',
      'мелодрама': 'мелодрама',
      'семейный': 'семейный',
      'военный': 'военный',
    };
    final genres = interests
        .map((interest) => interest.trim().toLowerCase())
        .map((interest) => genreAliases[interest])
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    if (genres.isEmpty) return const [];

    final source = KinopoiskCatalogSource(
      apiKey: kinopoiskApiKey,
      client: client,
    );
    final kinds = switch (type) {
      'Фильм' => const [MediaSourceKind.movie],
      'Сериал' => const [MediaSourceKind.series],
      _ => const [MediaSourceKind.movie, MediaSourceKind.series],
    };
    try {
      final results = await Future.wait(
        kinds.map((kind) => source.fetchByGenres(kind: kind, genres: genres)),
      );
      final unique = <String, MediaItem>{};
      for (final item in results.expand((items) => items)) {
        unique.putIfAbsent(item.id, () => item);
      }
      return List<MediaItem>.unmodifiable(unique.values);
    } on Object {
      return const [];
    }
  }

  Future<MediaDetails?> _loadPoiskKinoDetails(MediaItem item) async {
    final id = item.id.substring('kinopoisk:'.length).trim();
    if (id.isEmpty || kinopoiskApiKey.trim().isEmpty) return null;
    final source = KinopoiskCatalogSource(
      apiKey: kinopoiskApiKey,
      client: client,
    );
    try {
      final data = await source.fetchDetails(id);
      if (data == null) return null;
      final genresPayload = data['genres'];
      final genres = genresPayload is List
          ? genresPayload
                .map(
                  (entry) => entry is Map<String, dynamic>
                      ? entry['name'] as String?
                      : entry is String
                      ? entry
                      : null,
                )
                .whereType<String>()
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList(growable: false)
          : item.categories;
      final premiere = data['premiere'];
      final premiereMap = premiere is Map<String, dynamic>
          ? premiere
          : const <String, dynamic>{};
      final releaseDate =
          (data['releaseDate'] as String? ??
                  data['release_date'] as String? ??
                  premiereMap['world'] as String? ??
                  premiereMap['russia'] as String? ??
                  '')
              .trim();
      final runtimeValue = data['movieLength'] ?? data['runtime'];
      final runtime = runtimeValue is num ? runtimeValue.toInt() : null;
      final backdropPayload = data['backdrop'];
      final backdropMap = backdropPayload is Map<String, dynamic>
          ? backdropPayload
          : const <String, dynamic>{};
      final backdrop = _validatedHttpUrl(
        backdropMap['url'] as String? ?? data['backdropUrl'] as String? ?? '',
      );
      final homepage = _validatedHttpUrl(data['homepage'] as String? ?? '');
      return MediaDetails(
        overview:
            (data['description'] as String? ??
                    data['shortDescription'] as String? ??
                    item.description)
                .trim(),
        genres: genres,
        cast: const [],
        runtimeMinutes: runtime != null && runtime > 0 ? runtime : null,
        releaseDate: releaseDate,
        backdropUrl: backdrop,
        homepage: homepage,
        franchiseId: 'kinopoisk:item:$id',
      );
    } on Object {
      return null;
    }
  }

  String _validatedHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return '';
    }
    return uri.toString();
  }

  Future<MediaDetails?> loadDetails(MediaItem item) async {
    if (item.id.startsWith('kinopoisk:')) {
      return _loadPoiskKinoDetails(item);
    }
    if (!isConfigured || !item.id.startsWith('tmdb:')) return null;
    final p = item.id.split(':');
    if (p.length != 3 || !{'movie', 'tv'}.contains(p[1])) return null;
    final uri = Uri.parse('$_api/${p[1]}/${p[2]}').replace(
      queryParameters: {'language': 'ru-RU', 'append_to_response': 'credits'},
    );
    try {
      final r = await _get(
        uri,
        headers: {
          'Authorization': '***',
          'accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));
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
      final collection = data['belongs_to_collection'];
      final collectionMap = collection is Map<String, dynamic>
          ? collection
          : const <String, dynamic>{};
      final collectionId = collectionMap['id'];
      // Load the catalog collection without waiting for AI research. The
      // details screen can render immediately in release order while the
      // franchise section resolves chronology in the background.
      final franchiseId = collectionId is num
          ? 'tmdb:collection:${collectionId.toInt()}'
          : 'tmdb:item:${item.id}';
      final franchiseEntries = collectionId is num
          ? await loadCollectionItems(collectionId.toInt())
          : const <MediaFranchiseEntry>[];
      final franchiseItems = p[1] == 'movie'
          ? franchiseEntries
                .where((entry) => entry.id != 'tmdb:movie:${p[2]}')
                .toList(growable: false)
          : franchiseEntries;
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
        franchiseName: collectionMap['name'] as String? ?? '',
        franchiseId: franchiseId,
        franchiseChronologyEntries: franchiseEntries,
        franchiseItems: franchiseItems,
      );
    } on Object {
      return null;
    }
  }

  /// Resolves cached/researched chronology without allowing the resolver
  /// to add or remove catalog entries. Any resolver failure safely falls back
  /// to the catalog's release-sorted collection.
  Future<List<MediaFranchiseEntry>> resolveFranchiseChronology({
    required String franchiseId,
    required List<MediaFranchiseEntry> entries,
  }) async {
    final resolver = franchiseChronologyResolver;
    if (resolver == null || entries.isEmpty) {
      return List<MediaFranchiseEntry>.unmodifiable(entries);
    }
    try {
      final resolved = await resolver(
        franchiseId: franchiseId,
        entries: List<MediaFranchiseEntry>.unmodifiable(entries),
      );
      final originalIds = entries.map((entry) => entry.id).toSet();
      final resolvedIds = resolved.map((entry) => entry.id).toSet();
      if (resolved.length != entries.length ||
          resolvedIds.length != resolved.length ||
          !resolvedIds.containsAll(originalIds)) {
        return List<MediaFranchiseEntry>.unmodifiable(entries);
      }
      return List<MediaFranchiseEntry>.unmodifiable(resolved);
    } on Object {
      return List<MediaFranchiseEntry>.unmodifiable(entries);
    }
  }

  /// Loads verified movie entries from the TMDB collection attached to a
  /// movie's details response. Similar/recommended titles are not treated as
  /// franchise members, and the currently open movie is omitted.
  Future<List<MediaFranchiseEntry>> loadCollectionItems(
    int collectionId, {
    int? currentMovieId,
  }) async {
    if (!isConfigured || collectionId <= 0) return const [];
    final uri = Uri.parse(
      '$_api/collection/$collectionId',
    ).replace(queryParameters: {'language': 'ru-RU'});
    try {
      final response = await _get(
        uri,
        headers: {
          'Authorization': '***',
          'accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) return const [];
      return parseCollectionParts(
        data['parts'],
        currentMovieId: currentMovieId,
      );
    } on Object {
      return const [];
    }
  }

  /// Parses only valid TMDB collection parts; no sequel/prequel relation is
  /// guessed from title similarity or release date.
  static List<MediaFranchiseEntry> parseCollectionParts(
    Object? payload, {
    int? currentMovieId,
  }) {
    if (payload is! List) return const [];
    final entries = <MediaFranchiseEntry>[];
    for (final raw in payload) {
      if (raw is! Map<String, dynamic>) continue;
      final id = raw['id'];
      final title = (raw['title'] as String? ?? '').trim();
      if (id is! num ||
          id <= 0 ||
          title.isEmpty ||
          id.toInt() == currentMovieId) {
        continue;
      }
      final poster = raw['poster_path'] as String?;
      entries.add(
        MediaFranchiseEntry(
          id: 'tmdb:movie:${id.toInt()}',
          title: title,
          overview: raw['overview'] as String? ?? '',
          releaseDate: raw['release_date'] as String? ?? '',
          posterUrl: poster == null ? '' : '$_poster$poster',
        ),
      );
    }
    entries.sort((a, b) {
      if (a.releaseDate.isEmpty && b.releaseDate.isNotEmpty) return 1;
      if (b.releaseDate.isEmpty && a.releaseDate.isNotEmpty) return -1;
      return a.releaseDate.compareTo(b.releaseDate);
    });
    return List<MediaFranchiseEntry>.unmodifiable(entries);
  }

  /// Orders franchise entries without inventing chronology metadata.
  /// Chronology is used only when every entry has a verified position and no
  /// entry is marked as spoiler-risky. Smart mode otherwise falls back to the
  /// intended release order.
  static List<MediaFranchiseEntry> orderFranchiseItems(
    List<MediaFranchiseEntry> entries,
    FranchiseViewingOrder order,
  ) {
    final result = List<MediaFranchiseEntry>.of(entries);
    if (order == FranchiseViewingOrder.release) return result;
    final chronologyOrders = result
        .map((entry) => entry.chronologyOrder)
        .whereType<int>()
        .toSet();
    final hasVerifiedChronology =
        result.isNotEmpty &&
        result.every((entry) => entry.chronologyOrder != null) &&
        chronologyOrders.length == result.length &&
        chronologyOrders.every((order) => order >= 1 && order <= result.length);
    final hasSpoilerRisk = result.any((entry) => entry.chronologySpoilerRisk);
    if (order == FranchiseViewingOrder.chronology && hasVerifiedChronology) {
      result.sort((a, b) => a.chronologyOrder!.compareTo(b.chronologyOrder!));
    } else if (order == FranchiseViewingOrder.smart &&
        hasVerifiedChronology &&
        !hasSpoilerRisk) {
      result.sort((a, b) => a.chronologyOrder!.compareTo(b.chronologyOrder!));
    } else {
      result.sort((a, b) {
        if (a.releaseDate.isEmpty && b.releaseDate.isNotEmpty) return 1;
        if (b.releaseDate.isEmpty && a.releaseDate.isNotEmpty) return -1;
        return a.releaseDate.compareTo(b.releaseDate);
      });
    }
    return List<MediaFranchiseEntry>.unmodifiable(result);
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
      final response = await _get(
        uri,
        headers: {
          'Authorization': '***',
          'accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));
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

class MediaFranchiseEntry {
  const MediaFranchiseEntry({
    required this.id,
    required this.title,
    required this.overview,
    required this.releaseDate,
    required this.posterUrl,
    this.chronologyOrder,
    this.chronologySpoilerRisk = false,
    this.chronologySourceUrl = '',
  });

  final String id;
  final String title;
  final String overview;
  final String releaseDate;
  final String posterUrl;

  /// Only populated by a source that verifies in-universe chronology.
  final int? chronologyOrder;

  /// True when the chronology position is known to reveal a major plot point.
  final bool chronologySpoilerRisk;

  /// HTTPS evidence used to verify this in-universe chronology position.
  final String chronologySourceUrl;
}

enum FranchiseViewingOrder { release, chronology, smart }

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
    this.franchiseName = '',
    this.franchiseId = '',
    this.franchiseChronologyEntries = const [],
    this.franchiseItems = const [],
  });
  final String overview;
  final List<String> genres;
  final List<MediaCastMember> cast;
  final int? runtimeMinutes;
  final String releaseDate, backdropUrl, homepage;
  final List<MediaCatalogSeason> seasons;
  final String franchiseName;
  final String franchiseId;

  /// Full catalog membership used for chronology research, including the
  /// currently opened movie; never displayed directly in the related carousel.
  final List<MediaFranchiseEntry> franchiseChronologyEntries;
  final List<MediaFranchiseEntry> franchiseItems;
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
