import 'package:flutter/material.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/presentation/player_page.dart';
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
  String _query = '';
  String? _selectedType;

  static const _types = ['Фильм', 'Сериал', 'Аниме'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.searchService.search(_query, type: _selectedType);
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
              widget.searchService.recommendedFor(widget.preferences),
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
          '02 // MEDIA INDEX',
          style: TextStyle(
            color: SystemCorePalette.muted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'МЕДИА-ХАБ',
          style: TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('media-search'),
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value),
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
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close),
                  ),
            filled: true,
            fillColor: SystemCorePalette.panel,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: _searchBorder(),
            enabledBorder: _searchBorder(),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
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
    if (items.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            'НЕТ СОВПАДЕНИЙ',
            style: TextStyle(color: SystemCorePalette.muted, fontSize: 12),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.separated(
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          return _MediaResultTile(
            item: item,
            preferredVoiceover: widget.searchService.preferredVoiceover(
              item,
              widget.preferences,
            ),
            onTap: () => _openPlayer(item),
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
                  );
                },
              ),
            ),
          ],
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
  const _MediaPosterCard({required this.item, required this.onTap});

  final MediaItem item;
  final VoidCallback onTap;

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
                child: _PosterImage(url: item.posterUrl),
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
  });

  final MediaItem item;
  final String? preferredVoiceover;
  final VoidCallback onTap;

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
                child: _PosterImage(url: item.posterUrl),
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
              const Icon(Icons.chevron_right, color: SystemCorePalette.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterImage extends StatelessWidget {
  const _PosterImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
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
