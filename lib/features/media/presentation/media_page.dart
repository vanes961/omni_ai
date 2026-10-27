import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/core/network/widgets/network_image_with_fallback.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/favorites/data/favorite_item.dart';
import 'package:omni_ai/features/favorites/data/favorites_repository.dart';
import 'package:omni_ai/features/favorites/presentation/favorites_page.dart';
import 'package:omni_ai/features/favorites/services/favorite_interest_analytics.dart';
import 'package:omni_ai/features/media/presentation/player_page.dart';
import 'package:omni_ai/features/media/presentation/media_details_page.dart';
import 'package:omni_ai/features/media/presentation/manga_catalog_page.dart';
import 'package:omni_ai/features/media/services/media_headers.dart';
import 'package:omni_ai/features/media/services/media_like_repository.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/media/services/media_catalog_token_store.dart';
import 'package:omni_ai/features/media/services/poiskkino_api_key_store.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class MediaPage extends StatefulWidget {
  const MediaPage({
    required this.preferences,
    this.searchService = MediaSearchService(),
    this.catalogTokenStore,
    this.playerFactory,
    this.onOpenCatalogSettings,
    super.key,
  });

  final UserPreferences preferences;
  final MediaSearchService searchService;
  final MediaCatalogTokenStore? catalogTokenStore;
  final MediaPlayerFactory? playerFactory;
  final VoidCallback? onOpenCatalogSettings;

  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> {
  final TextEditingController _searchController = TextEditingController();
  late MediaSearchService _searchService;
  late final MediaCatalogTokenStore _catalogTokenStore;
  late final PoiskKinoApiKeyStore _poiskKinoKeyStore;
  final FavoritesRepository _favoritesRepository = FavoritesRepository();
  final MediaLikeRepository _likeRepository = MediaLikeRepository();
  final FavoriteInterestAnalytics _interestAnalytics =
      const FavoriteInterestAnalytics();
  List<FavoriteItem> _favoriteItems = const <FavoriteItem>[];
  List<FavoriteItem> _likedItems = const <FavoriteItem>[];
  Set<String> _likedIds = <String>{};
  String _query = '';
  String? _selectedType;
  String? _selectedGenre;
  bool _sortByRating = false;
  Timer? _searchDebounce;
  Future<List<MediaItem>>? _onlineSearch;
  List<MediaItem> _onlineTrending = const [];
  List<MediaItem> _onlineRecommendations = const [];
  bool _loadingTrending = false;

  static const _types = ['Фильм', 'Сериал', 'Аниме'];

  @override
  void initState() {
    super.initState();
    _searchService = widget.searchService;
    _catalogTokenStore =
        widget.catalogTokenStore ?? SecureMediaCatalogTokenStore();
    _poiskKinoKeyStore = SecurePoiskKinoApiKeyStore();
    unawaited(_loadCatalogToken());
    _loadFavoriteInterests();
  }

  Future<void> _loadCatalogToken() async {
    // Start from the injected/build-time configuration immediately. Secure
    // storage can be slow or unavailable in widget tests and on some devices.
    final initialService = _searchService;
    if (initialService.isSearchConfigured) {
      unawaited(_loadTrending());
      unawaited(_loadRecommendations());
    }

    var secureTokenApplied = false;
    try {
      final token = await _catalogTokenStore.readToken();
      if (!mounted) return;
      if (token != null && token.trim().isNotEmpty) {
        setState(() {
          _searchService = _searchService.withAccessToken(token);
          secureTokenApplied = true;
          if (_query.trim().isNotEmpty) {
            _onlineSearch = _searchService.searchOnline(
              _query,
              type: _selectedType,
            );
          }
        });
      }
    } on Object {
      // Secure storage is optional; keep the injected/build-time token.
    }

    if (!mounted) return;
    // Reload only when the secure token replaced the initial configuration.
    // Otherwise the first request is already running (or there is no token).
    if (secureTokenApplied) {
      unawaited(_loadTrending());
      unawaited(_loadRecommendations());
    }
    unawaited(_loadPoiskKinoApiKey());
  }

  Future<void> _loadPoiskKinoApiKey() async {
    try {
      final key = await _poiskKinoKeyStore.readApiKey();
      if (!mounted || key == null || key.trim().isEmpty) return;
      setState(() {
        _searchService = _searchService.withKinopoiskApiKey(key);
        if (_query.trim().isNotEmpty) {
          _onlineSearch = _searchService.searchOnline(
            _query,
            type: _selectedType,
          );
        }
      });
      unawaited(_loadTrending());
      unawaited(_loadRecommendations());
    } on Object {
      // PoiskKino is optional and must not block TMDB catalog access.
    }
  }

  Future<void> _loadTrending() async {
    final service = _searchService;
    if (!service.isSearchConfigured) return;
    if (mounted) setState(() => _loadingTrending = true);
    final items = await service.fetchTrendingOnline(type: _selectedType);
    if (!mounted || !identical(service, _searchService)) return;
    setState(() {
      _onlineTrending = _rankByFavoriteInterests(items);
      _loadingTrending = false;
    });
  }

  Future<void> _loadFavoriteInterests() async {
    try {
      final items = await _favoritesRepository.getAll();
      final liked = await _likeRepository.getAll();
      if (!mounted) return;
      setState(() {
        _favoriteItems = items;
        _likedItems = liked;
        _likedIds = liked.map((item) => item.id).toSet();
      });
      unawaited(_loadRecommendations());
    } catch (_) {
      // Search remains usable if local favorite analytics cannot be read.
    }
  }

  Future<void> _loadRecommendations() async {
    if (!_searchService.isConfigured) return;
    final requestedType = _selectedType;
    final favorites = [..._favoriteItems, ..._likedItems];
    final interests = favorites
        .expand((item) => item.interests)
        .map((interest) => interest.trim())
        .where((interest) => interest.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (interests.isEmpty) {
      if (mounted) {
        setState(() {
          _onlineRecommendations = const [];
        });
      }
      return;
    }
    final service = _searchService;
    final items = await service.fetchRecommendationsOnline(
      interests: interests,
      type: requestedType,
    );
    if (!mounted ||
        !identical(service, _searchService) ||
        _selectedType != requestedType) {
      return;
    }
    final savedIds = favorites.map((item) => item.id).toSet();
    final ranked = _rankByFavoriteInterests(items)
        .where((item) => !savedIds.contains(item.id))
        .take(20)
        .toList(growable: false);
    setState(() {
      _onlineRecommendations = ranked;
    });
  }

  List<MediaItem> _rankByFavoriteInterests(List<MediaItem> items) {
    final profile = _interestAnalytics.analyze([
      ..._favoriteItems,
      ..._likedItems,
    ]);
    return _interestAnalytics.rank(items, profile);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _rankByFavoriteInterests(
      _searchService.search(_query, type: _selectedType),
    );
    // Selecting a media type is a browse filter, not a text search.
    // Keep the trending carousel visible and let the service return that type.
    final isFiltering = _query.isNotEmpty || _selectedGenre != null;

    return Material(
      color: Colors.transparent,
      child: CustomScrollView(
        key: const ValueKey('media-page-scroll'),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            sliver: SliverToBoxAdapter(child: _buildHeader()),
          ),
          if (isFiltering)
            _buildSearchResults(results)
          else if (_loadingTrending && _onlineTrending.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_onlineTrending.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        SystemCorePalette.panelElevated,
                        SystemCorePalette.panel,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: SystemCorePalette.green.withValues(alpha: 0.24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: SystemCorePalette.green.withValues(alpha: 0.05),
                        blurRadius: 28,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: SystemCorePalette.green.withValues(
                            alpha: 0.08,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: SystemCorePalette.green.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        child: const Icon(
                          Icons.travel_explore,
                          size: 32,
                          color: SystemCorePalette.green,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _searchService.isConfigured
                            ? 'НЕ УДАЛОСЬ ЗАГРУЗИТЬ ТРЕНДЫ'
                            : 'ПОДКЛЮЧИТЕ КАТАЛОГ TMDB',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _searchService.isConfigured
                            ? 'Не удалось получить тренды TMDB. Проверьте интернет и токен в настройках каталога. Источники воспроизведения не подключены, поэтому карточки пока не запускают видео.'
                            : 'Чтобы показать актуальные фильмы, сериалы и аниме, добавьте TMDB Read Access Token в настройках каталога. Демо-контент и фиктивные ссылки отключены.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: SystemCorePalette.muted,
                          height: 1.5,
                        ),
                      ),
                      if (widget.onOpenCatalogSettings != null) ...[
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          key: const ValueKey('open-media-catalog-settings'),
                          onPressed: widget.onOpenCatalogSettings,
                          icon: const Icon(Icons.settings_outlined, size: 17),
                          label: const Text('НАСТРОИТЬ КАТАЛОГ'),
                          style: FilledButton.styleFrom(
                            backgroundColor: SystemCorePalette.green,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 15,
                            color: SystemCorePalette.green,
                          ),
                          SizedBox(width: 7),
                          Text(
                            'БЕЗ ДЕМО-ДАННЫХ',
                            style: TextStyle(
                              color: SystemCorePalette.green,
                              fontSize: 10,
                              letterSpacing: 1,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            _buildCarouselSection('ТРЕНДЫ', _onlineTrending),
            _buildCarouselSection(
              'РЕКОМЕНДОВАНО ДЛЯ ТЕБЯ',
              _onlineRecommendations,
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SystemCorePalette.panelElevated, SystemCorePalette.panel],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: SystemCorePalette.green.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OMNI AI  //  MEDIA',
            style: TextStyle(
              color: SystemCorePalette.muted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'МЕДИА-ХАБ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('open-favorites'),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => FavoritesPage()),
                  );
                  await _loadFavoriteInterests();
                },
                icon: const Icon(Icons.favorite_border, size: 16),
                label: const Text('ИЗБРАННОЕ'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('open-manga-catalog'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MangaCatalogPage(),
                ),
              ),
              icon: const Icon(Icons.menu_book_rounded, size: 17),
              label: const Text('МАНГА • РУССКАЯ ЧИТАЛКА'),
              style: OutlinedButton.styleFrom(
                foregroundColor: SystemCorePalette.green,
                side: BorderSide(
                  color: SystemCorePalette.green.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('media-search'),
            controller: _searchController,
            onChanged: (value) {
              _searchDebounce?.cancel();
              setState(() {
                _query = value;
                _onlineSearch = null;
              });
              _searchDebounce = Timer(const Duration(milliseconds: 350), () {
                if (mounted) {
                  setState(() {
                    _onlineSearch = _searchService.searchOnline(
                      value,
                      type: _selectedType,
                    );
                  });
                }
              });
            },
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Найти фильм, сериал или аниме',
              hintStyle: const TextStyle(color: SystemCorePalette.muted),
              prefixIcon: const Icon(
                Icons.search,
                color: SystemCorePalette.green,
              ),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Очистить поиск',
                      onPressed: () {
                        _searchDebounce?.cancel();
                        _searchController.clear();
                        setState(() {
                          _query = '';
                          _onlineSearch = null;
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: SystemCorePalette.panel,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: _searchBorder(),
              enabledBorder: _searchBorder(),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: SystemCorePalette.green),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _TypeFilter(
                  label: 'Все',
                  selected: _selectedType == null,
                  onTap: () => _selectMediaType(null),
                ),
                for (final type in _types)
                  _TypeFilter(
                    label: type,
                    selected: _selectedType == type,
                    onTap: () => _selectMediaType(type),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectMediaType(String? type) {
    setState(() {
      _selectedType = type;
      _onlineSearch = null;
    });
    unawaited(_loadTrending());
    unawaited(_loadRecommendations());
    if (_query.trim().isEmpty) return;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _onlineSearch = _searchService.searchOnline(
          _query,
          type: _selectedType,
        );
      });
    });
  }

  OutlineInputBorder _searchBorder() => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(
      color: SystemCorePalette.muted.withValues(alpha: 0.35),
    ),
  );

  Widget _buildSearchResults(List<MediaItem> items) {
    return SliverToBoxAdapter(
      child: FutureBuilder<List<MediaItem>>(
        future: _onlineSearch,
        builder: (context, snapshot) {
          final combined = [...items];
          for (final onlineItem in snapshot.data ?? const <MediaItem>[]) {
            final duplicate = combined.any(
              (item) =>
                  item.title.toLowerCase() == onlineItem.title.toLowerCase(),
            );
            if (!duplicate &&
                (_selectedType == null || onlineItem.type == _selectedType)) {
              combined.add(onlineItem);
            }
          }

          final availableGenres =
              combined
                  .expand((item) => item.categories)
                  .map((genre) => genre.trim())
                  .where((genre) => genre.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();
          final filtered = combined
              .where(
                (item) =>
                    _selectedGenre == null ||
                    item.categories.any(
                      (genre) =>
                          genre.toLowerCase() == _selectedGenre!.toLowerCase(),
                    ),
              )
              .toList();
          final rankedCombined = _rankByFavoriteInterests(filtered).toList();
          if (_sortByRating) {
            rankedCombined.sort((a, b) => b.rating.compareTo(a.rating));
          }

          if (rankedCombined.isEmpty &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (rankedCombined.isEmpty) {
            final message =
                _query.trim().isNotEmpty && !_searchService.isSearchConfigured
                ? 'ОНЛАЙН-КАТАЛОГ НЕ НАСТРОЕН: отсутствует TMDB_ACCESS_TOKEN. Реальный поиск недоступен.'
                : 'КАТАЛОГ И ИСТОЧНИКИ ВОСПРОИЗВЕДЕНИЯ ПОКА НЕ ПОДКЛЮЧЕНЫ.';
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: SystemCorePalette.muted,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(minHeight: 2),
              if (availableGenres.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('media-genre-all'),
                        label: const Text('Все жанры'),
                        selected: _selectedGenre == null,
                        onSelected: (_) =>
                            setState(() => _selectedGenre = null),
                      ),
                      for (final genre in availableGenres)
                        ChoiceChip(
                          key: ValueKey('media-genre-$genre'),
                          label: Text(genre),
                          selected: _selectedGenre == genre,
                          onSelected: (_) => setState(
                            () => _selectedGenre = _selectedGenre == genre
                                ? null
                                : genre,
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilterChip(
                    key: const ValueKey('media-sort-rating'),
                    label: const Text('Сначала высокий рейтинг'),
                    selected: _sortByRating,
                    onSelected: (selected) =>
                        setState(() => _sortByRating = selected),
                  ),
                ),
              ),
              ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rankedCombined.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = rankedCombined[index];
                  return _MediaResultTile(
                    item: item,
                    onTap: () => _openDetails(item),
                    onFavorite: () => _saveFavorite(item),
                    isLiked: _likedIds.contains(item.id),
                    onLike: () => _toggleLike(item),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCarouselSection(String title, List<MediaItem> items) {
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 254,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _MediaPosterCard(
                    item: item,
                    onTap: () => _openDetails(item),
                    onFavorite: () => _saveFavorite(item),
                    isLiked: _likedIds.contains(item.id),
                    onLike: () => _toggleLike(item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveFavorite(MediaItem item) async {
    final category = switch (item.type.toLowerCase()) {
      'фильм' || 'movie' => FavoriteCategory.movie,
      'сериал' || 'series' => FavoriteCategory.series,
      'аниме' || 'anime' => FavoriteCategory.anime,
      _ => null,
    };
    if (category == null) return;
    await _favoritesRepository.add(
      FavoriteItem(
        id: item.id,
        title: item.title,
        category: category,
        addedAt: DateTime.now(),
        description: item.description,
        interests: item.categories,
        imageUrl: item.posterUrl.isEmpty ? null : item.posterUrl,
        sourceUrl: item.videoUrl.isEmpty ? null : item.videoUrl,
      ),
    );
    await _loadFavoriteInterests();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('«${item.title}» добавлено в «${category.label}»'),
      ),
    );
  }

  Future<void> _toggleLike(MediaItem item) async {
    final category = switch (item.type.toLowerCase()) {
      'фильм' || 'movie' => FavoriteCategory.movie,
      'сериал' || 'series' => FavoriteCategory.series,
      'аниме' || 'anime' => FavoriteCategory.anime,
      _ => null,
    };
    if (category == null) return;
    final liked = await _likeRepository.toggle(
      FavoriteItem(
        id: item.id,
        title: item.title,
        category: category,
        addedAt: DateTime.now(),
        description: item.description,
        interests: item.categories,
        imageUrl: item.posterUrl.isEmpty ? null : item.posterUrl,
        sourceUrl: item.videoUrl.isEmpty ? null : item.videoUrl,
      ),
    );
    await _loadFavoriteInterests();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          liked
              ? 'Лайк сохранён — рекомендации будут учитывать этот интерес'
              : 'Лайк убран из анализа интересов',
        ),
      ),
    );
  }

  void _openDetails(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaDetailsPage(
          item: item,
          searchService: _searchService,
          preferences: widget.preferences,
          playerFactory: widget.playerFactory,
        ),
      ),
    );
  }
}

class _TypeFilter extends StatelessWidget {
  const _TypeFilter({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: SystemCorePalette.green.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          color: selected ? SystemCorePalette.green : SystemCorePalette.muted,
          fontSize: 11,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(
            color: selected
                ? SystemCorePalette.green
                : SystemCorePalette.border,
          ),
        ),
      ),
    );
  }
}

class _MediaPosterCard extends StatelessWidget {
  const _MediaPosterCard({
    required this.item,
    required this.onTap,
    required this.onFavorite,
    required this.isLiked,
    required this.onLike,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final bool isLiked;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 144,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 144,
                height: 164,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _PosterImage(
                      url: item.posterUrl,
                      fallbackUrls: item.posterFallbackUrls,
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton.filledTonal(
                            tooltip: 'В избранное',
                            onPressed: onFavorite,
                            icon: const Icon(Icons.favorite_border, size: 18),
                          ),
                          IconButton.filledTonal(
                            tooltip: isLiked ? 'Убрать лайк' : 'Нравится',
                            onPressed: onLike,
                            icon: Icon(
                              isLiked
                                  ? Icons.thumb_up
                                  : Icons.thumb_up_outlined,
                              size: 17,
                              color: isLiked ? SystemCorePalette.green : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(
                    Icons.star,
                    size: 12,
                    color: SystemCorePalette.green,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    item.rating.toStringAsFixed(1),
                    style: const TextStyle(
                      color: SystemCorePalette.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              if (item.voiceovers.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  item.voiceovers.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SystemCorePalette.muted,
                    fontSize: 8,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaResultTile extends StatelessWidget {
  const _MediaResultTile({
    required this.item,
    required this.onTap,
    required this.onFavorite,
    required this.isLiked,
    required this.onLike,
  });

  final MediaItem item;
  final VoidCallback? onTap;
  final VoidCallback onFavorite;
  final bool isLiked;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SystemCorePalette.panel,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                height: 86,
                child: _PosterImage(
                  url: item.posterUrl,
                  fallbackUrls: item.posterFallbackUrls,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${item.type}  ·  ★ ${item.rating.toStringAsFixed(1)}',
                      style: const TextStyle(
                        color: SystemCorePalette.muted,
                        fontSize: 10,
                      ),
                    ),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SystemCorePalette.muted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'В избранное',
                    onPressed: onFavorite,
                    icon: const Icon(Icons.favorite_border),
                  ),
                  IconButton(
                    tooltip: isLiked ? 'Убрать лайк' : 'Нравится',
                    onPressed: onLike,
                    icon: Icon(
                      isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                      color: isLiked ? SystemCorePalette.green : null,
                    ),
                  ),
                ],
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: SystemCorePalette.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterImage extends StatelessWidget {
  const _PosterImage({required this.url, this.fallbackUrls = const []});

  final String url;
  final List<String> fallbackUrls;

  @override
  Widget build(BuildContext context) {
    return NetworkImageWithFallback(
      url: url,
      fallbackUrls: fallbackUrls,
      fit: BoxFit.cover,
      headers: MediaHeaders.getHeaders(url),
      errorBuilder: (context, error, stackTrace) => Container(
        color: SystemCorePalette.panel,
        alignment: Alignment.center,
        child: const Icon(
          Icons.movie_outlined,
          color: SystemCorePalette.muted,
          size: 28,
        ),
      ),
    );
  }
}
