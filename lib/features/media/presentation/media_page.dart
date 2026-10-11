import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/core/network/widgets/network_image_with_fallback.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/favorites/data/favorite_item.dart';
import 'package:omni_ai/features/favorites/data/favorites_repository.dart';
import 'package:omni_ai/features/favorites/presentation/favorites_page.dart';
import 'package:omni_ai/features/favorites/services/favorite_interest_analytics.dart';
import 'package:omni_ai/features/media/presentation/player_page.dart';
import 'package:omni_ai/features/media/services/media_headers.dart';
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
  final FavoriteInterestAnalytics _interestAnalytics = const FavoriteInterestAnalytics();
  List<FavoriteItem> _favoriteItems = const <FavoriteItem>[];
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
      if (!mounted) return;
      setState(() => _favoriteItems = items);
    } catch (_) {
      // Search remains usable if local favorite analytics cannot be read.
    }
  }

  List<MediaItem> _rankByFavoriteInterests(List<MediaItem> items) {
    final profile = _interestAnalytics.analyze(_favoriteItems);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'KAIROS  //  MEDIA DECK',
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
                  MaterialPageRoute<void>(
                    builder: (_) => FavoritesPage(),
                  ),
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
                  _onlineSearch = widget.searchService.searchOnline(value);
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
            focusedBorder: const OutlineInputBorder(
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
    );
  }

  OutlineInputBorder _searchBorder() => OutlineInputBorder(
    borderRadius: BorderRadius.zero,
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
                  'НЕТ СОВПАДЕНИЙ',
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
                    preferredVoiceover: widget.searchService.preferredVoiceover(
                      item,
                      widget.preferences,
                    ),
                    onTap: item.videoUrl.isEmpty
                        ? null
                        : () => _openPlayer(item),
                    onFavorite: () => _saveFavorite(item),
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
      SnackBar(content: Text('«${item.title}» добавлено в «${category.label}»')),
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
  });

  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

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
                      child: IconButton.filledTonal(
                        tooltip: 'В избранное',
                        onPressed: onFavorite,
                        icon: const Icon(Icons.favorite_border, size: 18),
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
    required this.preferredVoiceover,
    required this.onTap,
    required this.onFavorite,
  });

  final MediaItem item;
  final String? preferredVoiceover;
  final VoidCallback? onTap;
  final VoidCallback onFavorite;

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
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: item.voiceovers.map((voiceover) {
                        final selected = voiceover == preferredVoiceover;
                        return Text(
                          voiceover,
                          style: TextStyle(
                            color: selected
                                ? SystemCorePalette.green
                                : Colors.white54,
                            fontSize: 9,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'В избранное',
                onPressed: onFavorite,
                icon: const Icon(Icons.favorite_border),
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
