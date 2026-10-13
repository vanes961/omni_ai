import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:omni_ai/core/network/widgets/network_image_with_fallback.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/favorites/data/favorite_item.dart';
import 'package:omni_ai/features/favorites/data/favorites_repository.dart';
import 'package:omni_ai/features/favorites/presentation/favorites_page.dart';
import 'package:omni_ai/features/favorites/services/favorite_interest_analytics.dart';
import 'package:omni_ai/features/media/presentation/player_page.dart';
import 'package:omni_ai/features/media/presentation/media_details_page.dart';
import 'package:omni_ai/features/media/services/media_headers.dart';
import 'package:omni_ai/features/media/services/media_like_repository.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class MediaPage extends StatefulWidget {
  const MediaPage({
    required this.preferences,
    this.searchService = const MediaSearchService(),
    this.playerFactory,
    super.key,
  });

  final UserPreferences preferences;
  final MediaSearchService searchService;
  final MediaPlayerFactory? playerFactory;

  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> {
  final TextEditingController _searchController = TextEditingController();
  final FavoritesRepository _favoritesRepository = FavoritesRepository();
  final MediaLikeRepository _likeRepository = MediaLikeRepository();
  final FavoriteInterestAnalytics _interestAnalytics =
      const FavoriteInterestAnalytics();
  List<FavoriteItem> _favoriteItems = const <FavoriteItem>[];
  List<FavoriteItem> _likedItems = const <FavoriteItem>[];
  Set<String> _likedIds = <String>{};
  String _query = '';
  String? _selectedType;
  Timer? _searchDebounce;
  Future<List<MediaItem>>? _onlineSearch;

  static const _types = ['Фильм', 'Сериал', 'Аниме'];

  @override
  void initState() {
    super.initState();
    _loadFavoriteInterests();
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
    } catch (_) {
      // Search remains usable if local favorite analytics cannot be read.
    }
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
      widget.searchService.search(_query, type: _selectedType),
    );
    final isFiltering = _query.isNotEmpty || _selectedType != null;

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
          else if (widget.searchService.trending.isEmpty)
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
                      const Text(
                        'МЕДИАКАТАЛОГ НЕ ПОДКЛЮЧЁН',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Демо-фильмы и фиктивные озвучки удалены. Откройте каталог ZONA кнопкой выше; встроенный поиск и воспроизведение подключим после подтверждения доступного интерфейса источника.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: SystemCorePalette.muted,
                          height: 1.5,
                        ),
                      ),
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
            _buildCarouselSection('ТРЕНДЫ', widget.searchService.trending),
            _buildCarouselSection(
              'РЕКОМЕНДОВАНО ДЛЯ ТЕБЯ',
              _rankByFavoriteInterests(
                widget.searchService.recommendedFor(widget.preferences),
              ),
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
          const SizedBox(height: 14),
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
                    _onlineSearch = widget.searchService.searchOnline(
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
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('open-zona-catalog'),
              onPressed: _openZonaCatalog,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('ОТКРЫТЬ КАТАЛОГ ZONA'),
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
                  onTap: () => setState(() => _selectedType = null),
                ),
                for (final type in _types)
                  _TypeFilter(
                    label: type,
                    selected: _selectedType == type,
                    onTap: () => setState(() => _selectedType = type),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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

          final rankedCombined = _rankByFavoriteInterests(combined);

          if (rankedCombined.isEmpty &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (rankedCombined.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'ВНУТРЕННИЙ КАТАЛОГ ПОКА НЕ ПОДКЛЮЧЁН. ОТКРОЙТЕ ZONA КНОПКОЙ ВЫШЕ.',
                  style: TextStyle(
                    color: SystemCorePalette.muted,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          }

          return Column(
            children: [
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(minHeight: 2),
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
                    onTap: () => _openPlayer(item),
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

  Future<void> _openZonaCatalog() async {
    await launchUrl(
      MediaSearchService.zonaCatalogUri,
      mode: LaunchMode.externalApplication,
    );
  }

  void _openDetails(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaDetailsPage(
          item: item,
          searchService: widget.searchService,
          preferences: widget.preferences,
          playerFactory: widget.playerFactory,
        ),
      ),
    );
  }

  void _openPlayer(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PlayerPage(
          item: item,
          preferences: widget.preferences,
          searchService: widget.searchService,
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
          color: selected ? SystemCorePalette.green : Colors.white70,
          fontSize: 11,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(
            color: selected ? SystemCorePalette.green : Colors.white24,
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
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ],
              ),
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
                          color: Colors.white70,
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
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/services/media_headers.dart';
import 'package:omni_ai/features/media/services/media_resume_position_store.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';
import 'package:video_player/video_player.dart';

typedef MediaPlayerFactory = MediaPlaybackController Function(Uri source);

abstract interface class MediaPlaybackController {
  bool get isInitialized;
  bool get isPlaying;
  double get aspectRatio;
  Duration get position;
  Duration get duration;

  Future<void> initialize();

  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(Duration position);

  Future<void> dispose();

  Widget buildView();
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    required this.item,
    required this.preferences,
    this.searchService = const MediaSearchService(),
    this.playerFactory,
    this.resumePositionStore,
    super.key,
  });

  final MediaItem item;
  final UserPreferences preferences;
  final MediaSearchService searchService;
  final MediaPlayerFactory? playerFactory;
  final MediaResumePositionStore? resumePositionStore;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late String? _selectedVoiceover;
  MediaPlaybackController? _player;
  Object? _playerError;
  bool _isLoading = true;
  int _selectedEpisode = 0;
  int _playerGeneration = 0;
  Timer? _progressTimer;
  final Set<int> _resumePromptedEpisodes = <int>{};
  final Set<int> _watchedEpisodes = <int>{};

  bool get _tracksEpisodeHistory {
    final type = widget.item.type.toLowerCase();
    return type.contains('сериал') ||
        type.contains('аниме') ||
        type.contains('series') ||
        type.contains('anime');
  }

  Future<void> _loadWatchedHistory() async {
    if (!_tracksEpisodeHistory || !_hasEpisodes) return;
    final watched = await _resumeStore.loadWatchedEpisodes(widget.item.id);
    if (!mounted) return;
    setState(() {
      _watchedEpisodes
        ..clear()
        ..addAll(
          watched.where(
            (index) => index >= 0 && index < widget.item.episodes.length,
          ),
        );
    });
  }

  MediaResumePositionStore get _resumeStore =>
      widget.resumePositionStore ?? SharedPreferencesMediaResumePositionStore();

  bool get _hasEpisodes => widget.item.episodes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadWatchedHistory());
    _progressTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_saveProgress()),
    );
    _selectedVoiceover = widget.searchService.preferredVoiceover(
      widget.item,
      widget.preferences,
    );
    _loadEpisode(0);
  }

  @override
  void dispose() {
    _playerGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    unawaited(_saveProgress());
    _player?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_saveProgress());
    }
  }

  Future<void> _saveProgress({
    MediaPlaybackController? player,
    int? episodeIndex,
  }) async {
    final activePlayer = player ?? _player;
    if (activePlayer == null || !activePlayer.isInitialized) return;
    final index = episodeIndex ?? _selectedEpisode;
    await _resumeStore.save(
      widget.item.id,
      index,
      activePlayer.position,
      activePlayer.duration,
    );
    final remaining = activePlayer.duration - activePlayer.position;
    if (_tracksEpisodeHistory &&
        _hasEpisodes &&
        activePlayer.duration > Duration.zero &&
        remaining <= const Duration(seconds: 15) &&
        index >= 0 &&
        index < widget.item.episodes.length) {
      await _resumeStore.markEpisodeWatched(widget.item.id, index);
      if (mounted && _watchedEpisodes.add(index)) {
        setState(() {});
      }
    }
  }

  Future<void> _offerResumeIfAvailable(
    MediaPlaybackController player,
    int episodeIndex,
    int generation,
  ) async {
    if (_resumePromptedEpisodes.contains(episodeIndex)) return;
    final savedPosition = await _resumeStore.load(widget.item.id, episodeIndex);
    if (!mounted || generation != _playerGeneration || savedPosition == null) {
      return;
    }
    _resumePromptedEpisodes.add(episodeIndex);
    final remaining = player.duration - savedPosition;
    if (savedPosition < const Duration(seconds: 10) ||
        (player.duration > Duration.zero &&
            remaining <= const Duration(seconds: 15))) {
      await _resumeStore.clear(widget.item.id, episodeIndex);
      return;
    }
    final shouldResume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: SystemCorePalette.panel,
        title: const Text(
          'Продолжить просмотр?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Вы остановились на ${_formatPosition(savedPosition)}.',
          style: const TextStyle(color: SystemCorePalette.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('НАЧАТЬ СНАЧАЛА'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ПРОДОЛЖИТЬ'),
          ),
        ],
      ),
    );
    if (!mounted || generation != _playerGeneration) return;
    if (shouldResume == true) {
      await player.seekTo(savedPosition);
    } else {
      await _resumeStore.clear(widget.item.id, episodeIndex);
    }
  }

  String _formatPosition(Duration position) {
    final hours = position.inHours;
    final minutes = position.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = position.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:$minutes:$seconds'
        : '${position.inMinutes}:$seconds';
  }

  Future<void> _loadEpisode(int episodeIndex) async {
    final generation = ++_playerGeneration;
    final oldPlayer = _player;
    final episode = _hasEpisodes ? widget.item.episodes[episodeIndex] : null;
    final defaultSource = episode?.videoUrl ?? widget.item.videoUrl;
    final availableVoiceovers = _availableVoiceoversFor(episode);
    final selectedVoiceover =
        availableVoiceovers.isNotEmpty &&
            !availableVoiceovers.contains(_selectedVoiceover)
        ? _preferredAvailableVoiceover(availableVoiceovers)
        : _selectedVoiceover;
    final voiceoverSource = selectedVoiceover == null
        ? null
        : episode?.voiceoverVideoUrls[selectedVoiceover] ??
              widget.item.voiceoverVideoUrls[selectedVoiceover];
    final source = voiceoverSource ?? defaultSource;
    final fallbackUrls = [
      if (voiceoverSource != null) defaultSource,
      ...widget.item.videoFallbackUrls,
      if (episode != null) ...episode.videoFallbackUrls,
    ];
    final sources = <String>{
      source.trim(),
      ...fallbackUrls.map((url) => url.trim()),
    }.where((url) => url.isNotEmpty).toList(growable: false);
    final playerFactory = widget.playerFactory ?? _videoPlayerFactory;

    unawaited(_saveProgress(player: oldPlayer, episodeIndex: _selectedEpisode));
    setState(() {
      _selectedEpisode = episodeIndex;
      if (selectedVoiceover != null) {
        _selectedVoiceover = selectedVoiceover;
      }
      _isLoading = true;
      _playerError = null;
      _player = null;
    });
    await _disposePlayer(oldPlayer);

    Object? playerError;
    for (var index = 0; index < sources.length; index++) {
      if (!mounted || generation != _playerGeneration) return;
      MediaPlaybackController? nextPlayer;
      try {
        nextPlayer = playerFactory(Uri.parse(sources[index]));
        await nextPlayer.initialize();
        if (!mounted || generation != _playerGeneration) {
          await _disposePlayer(nextPlayer);
          return;
        }
        setState(() {
          _player = nextPlayer;
          _isLoading = false;
        });
        await _offerResumeIfAvailable(nextPlayer, episodeIndex, generation);
        return;
      } on PlatformException catch (error) {
        playerError = error;
        await _disposePlayer(nextPlayer);
      } on Object catch (error) {
        playerError = error;
        await _disposePlayer(nextPlayer);
      }
    }
    if (!mounted || generation != _playerGeneration) return;
    setState(() {
      _playerError = playerError;
      _isLoading = false;
    });
  }

  Future<void> _togglePlayback(MediaPlaybackController player) async {
    try {
      if (player.isPlaying) {
        await player.pause();
      } else {
        await player.play();
      }
      if (mounted && identical(_player, player)) {
        setState(() => _playerError = null);
      }
    } on Object catch (error) {
      if (mounted && identical(_player, player)) {
        setState(() => _playerError = error);
      }
    }
  }

  Future<void> _disposePlayer(MediaPlaybackController? player) async {
    if (player == null) return;
    try {
      await player.dispose();
    } on Object {
      // A dispose failure must not prevent trying the next stream source.
    }
  }

  @override
  Widget build(BuildContext context) {
    final episodes = widget.item.episodes;

    return Scaffold(
      backgroundColor: SystemCorePalette.background,
      appBar: AppBar(
        title: const Text('OMNI // PLAYER'),
        backgroundColor: SystemCorePalette.background,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildPlayerSurface(),
          const SizedBox(height: 18),
          Text(
            widget.item.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${widget.item.type}  ·  ★ ${widget.item.rating.toStringAsFixed(1)}',
            style: const TextStyle(
              color: SystemCorePalette.muted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 20),
          if (_tracksEpisodeHistory && episodes.isNotEmpty) ...[
            Text(
              'ПРОСМОТРЕНО: ${_watchedEpisodes.length} ИЗ ${episodes.length} СЕРИЙ',
              key: const ValueKey('watched-episode-count'),
              style: const TextStyle(
                color: SystemCorePalette.green,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (episodes.length > 1) ...[
            const _PlayerSectionLabel('ВЫБОР СЕРИИ'),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: const ValueKey('episode-selector'),
              initialValue: _selectedEpisode,
              isExpanded: true,
              dropdownColor: SystemCorePalette.panel,
              decoration: _selectorDecoration(),
              items: [
                for (var index = 0; index < episodes.length; index++)
                  DropdownMenuItem(
                    value: index,
                    child: Text(
                      '${_watchedEpisodes.contains(index) ? '✓  ' : ''}${episodes[index].label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (index) {
                if (index != null && index != _selectedEpisode) {
                  _loadEpisode(index);
                }
              },
            ),
            const SizedBox(height: 18),
          ],
          if (widget.item.voiceovers.isNotEmpty) ...[
            const _PlayerSectionLabel('ОЗВУЧКА'),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final episode = _hasEpisodes
                    ? widget.item.episodes[_selectedEpisode]
                    : null;
                final availableVoiceovers = _availableVoiceoversFor(episode);
                if (availableVoiceovers.isEmpty) {
                  return Text(
                    widget.item.voiceovers.join(' · '),
                    style: const TextStyle(
                      color: SystemCorePalette.muted,
                      fontSize: 12,
                    ),
                  );
                }
                return DropdownButtonFormField<String>(
                  key: const ValueKey('voiceover-selector'),
                  initialValue: availableVoiceovers.contains(_selectedVoiceover)
                      ? _selectedVoiceover
                      : availableVoiceovers.first,
                  isExpanded: true,
                  dropdownColor: SystemCorePalette.panel,
                  decoration: _selectorDecoration(),
                  items: [
                    for (final voiceover in availableVoiceovers)
                      DropdownMenuItem(
                        value: voiceover,
                        child: Text(
                          voiceover,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (voiceover) {
                    if (voiceover == null || voiceover == _selectedVoiceover) {
                      return;
                    }
                    setState(() => _selectedVoiceover = voiceover);
                    _loadEpisode(_selectedEpisode);
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlayerSurface() {
    final player = _player;
    return AspectRatio(
      aspectRatio: player?.aspectRatio ?? 16 / 9,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.black),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (player?.isInitialized ?? false)
              player!.buildView()
            else if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  color: SystemCorePalette.green,
                ),
              )
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.play_disabled,
                        color: SystemCorePalette.muted,
                        size: 34,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ВИДЕО НЕДОСТУПНО НА ЭТОЙ ПЛАТФОРМЕ',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                      if (_playerError != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          _playerError.runtimeType.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: SystemCorePalette.muted,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if ((player?.isInitialized ?? false) && _playerError != null)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    border: Border.all(color: SystemCorePalette.green),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'ОШИБКА ВОСПРОИЗВЕДЕНИЯ: ${_playerError.runtimeType}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ),
            if (player?.isInitialized ?? false)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 52,
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: IconButton(
                    tooltip: player!.isPlaying ? 'Пауза' : 'Воспроизвести',
                    onPressed: () => _togglePlayback(player),
                    icon: Icon(
                      player.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<String> _availableVoiceoversFor(MediaEpisode? episode) {
    final episodeSources =
        episode?.voiceoverVideoUrls ?? const <String, String>{};
    final sources = episodeSources.isNotEmpty
        ? episodeSources
        : widget.item.voiceoverVideoUrls;
    return [
      for (final voiceover in widget.item.voiceovers)
        if (sources.containsKey(voiceover) &&
            sources[voiceover]!.trim().isNotEmpty)
          voiceover,
    ];
  }

  String? _preferredAvailableVoiceover(List<String> available) {
    for (final preferred in widget.preferences.voiceDubbing) {
      for (final voiceover in available) {
        if (voiceover.toLowerCase() == preferred.trim().toLowerCase()) {
          return voiceover;
        }
      }
    }
    return available.first;
  }

  InputDecoration _selectorDecoration() => InputDecoration(
    filled: true,
    fillColor: SystemCorePalette.panel,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(
        color: SystemCorePalette.muted.withValues(alpha: 0.4),
      ),
    ),
  );
}

class _PlayerSectionLabel extends StatelessWidget {
  const _PlayerSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: SystemCorePalette.muted,
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

MediaPlaybackController _videoPlayerFactory(Uri source) {
  return _VideoPlayerAdapter(source);
}

class _VideoPlayerAdapter implements MediaPlaybackController {
  _VideoPlayerAdapter(Uri source)
    : _controller = VideoPlayerController.networkUrl(
        source,
        httpHeaders: MediaHeaders.getHeaders(source.toString()),
      );

  final VideoPlayerController _controller;

  @override
  bool get isInitialized => _controller.value.isInitialized;

  @override
  bool get isPlaying => _controller.value.isPlaying;

  @override
  Duration get position => _controller.value.position;

  @override
  Duration get duration => _controller.value.duration;

  @override
  double get aspectRatio => _controller.value.aspectRatio > 0
      ? _controller.value.aspectRatio
      : 16 / 9;

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Future<void> dispose() => _controller.dispose();

  @override
  Widget buildView() => VideoPlayer(_controller);
}
