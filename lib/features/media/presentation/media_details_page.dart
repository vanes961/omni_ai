import 'dart:async';

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
            const _Label('РОССИЙСКИЕ ВИДЕОИСТОЧНИКИ'),
            const SizedBox(height: 6),
            const Text(
              'Бесплатный просмотр зависит от наличия фильма, региона и правил '
              'самого сервиса. OMNI AI не обходит ограничения доступа.',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.play_circle_outline,
                color: SystemCorePalette.green,
              ),
              title: const Text(
                'Найти на RUTUBE',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Бесплатные видео и часть фильмов',
                style: TextStyle(color: Colors.white54),
              ),
              trailing: const Icon(
                Icons.open_in_new,
                color: SystemCorePalette.muted,
                size: 18,
              ),
              onTap: () => _openProvider(
                Uri.https('rutube.ru', '/search/', {'query': item.title}),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.video_library_outlined,
                color: SystemCorePalette.green,
              ),
              title: const Text(
                'Найти в VK Видео',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Ролики, трейлеры и доступные публикации',
                style: TextStyle(color: Colors.white54),
              ),
              trailing: const Icon(
                Icons.open_in_new,
                color: SystemCorePalette.muted,
                size: 18,
              ),
              onTap: () => _openProvider(
                Uri.https('vk.com', '/video', {'q': item.title}),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.local_movies_outlined,
                color: SystemCorePalette.green,
              ),
              title: const Text(
                'Каталог PREMIER',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Есть отдельный раздел бесплатного контента',
                style: TextStyle(color: Colors.white54),
              ),
              trailing: const Icon(
                Icons.open_in_new,
                color: SystemCorePalette.muted,
                size: 18,
              ),
              onTap: () => _openProvider(Uri.https('premier.one', '/')),
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
            if (d?.franchiseItems.isNotEmpty == true)
              _FranchiseSection(
                name: d!.franchiseName,
                items: d.franchiseItems,
                chronologyEntries: d.franchiseChronologyEntries,
                franchiseId: d.franchiseId,
                searchService: searchService,
                preferences: preferences,
                playerFactory: playerFactory,
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
            if (item.videoUrl.trim().isEmpty &&
                !item.videoSources.any(
                  (source) => source.url.trim().isNotEmpty,
                ))
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: SystemCorePalette.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: SystemCorePalette.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: SystemCorePalette.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.link_off_rounded,
                        color: SystemCorePalette.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ВИДЕОИСТОЧНИК НЕ ПОДКЛЮЧЁН',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.35,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'TMDB предоставляет карточку, постер и описание, но не сам фильм. '
                            'Добавь доступный тебе HTTP(S)-поток или magnet-ссылку. '
                            'Для magnet нужен настроенный TorrServer.',
                            style: TextStyle(
                              color: SystemCorePalette.muted,
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (item.videoUrl.trim().isNotEmpty ||
                item.videoSources.any(
                  (source) => source.url.trim().isNotEmpty,
                ))
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

class _FranchiseSection extends StatefulWidget {
  const _FranchiseSection({
    required this.name,
    required this.items,
    this.chronologyEntries = const [],
    this.franchiseId = '',
    required this.searchService,
    required this.preferences,
    required this.playerFactory,
  });

  final String name;
  final List<MediaFranchiseEntry> items;
  final List<MediaFranchiseEntry> chronologyEntries;
  final String franchiseId;
  final MediaSearchService searchService;
  final UserPreferences preferences;
  final MediaPlayerFactory? playerFactory;

  @override
  State<_FranchiseSection> createState() => _FranchiseSectionState();
}

class _FranchiseSectionState extends State<_FranchiseSection> {
  FranchiseViewingOrder _order = FranchiseViewingOrder.smart;
  late List<MediaFranchiseEntry> _items;
  bool _isResolvingChronology = false;

  @override
  void initState() {
    super.initState();
    _items = List<MediaFranchiseEntry>.of(widget.items);
    if (widget.franchiseId.isNotEmpty && widget.chronologyEntries.isNotEmpty) {
      _isResolvingChronology = true;
      unawaited(_resolveChronology());
    }
  }

  Future<void> _resolveChronology() async {
    try {
      final resolved = await widget.searchService.resolveFranchiseChronology(
        franchiseId: widget.franchiseId,
        entries: widget.chronologyEntries,
      );
      final visibleIds = widget.items.map((entry) => entry.id).toSet();
      if (!mounted) return;
      setState(() {
        _items = resolved
            .where((entry) => visibleIds.contains(entry.id))
            .toList(growable: false);
        _isResolvingChronology = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _isResolvingChronology = false);
    }
  }

  bool get _hasVerifiedChronology =>
      _items.isNotEmpty &&
      _items.every((entry) => entry.chronologyOrder != null);

  Future<void> _selectChronology() async {
    if (!_hasVerifiedChronology) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Подтверждённая хронология этой франшизы пока недоступна. '
            'Можно выбрать порядок выхода или умный порядок.',
          ),
        ),
      );
      return;
    }
    final hasSpoilers = _items.any((entry) => entry.chronologySpoilerRisk);
    if (hasSpoilers) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: SystemCorePalette.panel,
          title: const Text(
            'Возможны спойлеры',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Хронологический порядок может раскрыть события или тайны '
            'раньше, чем они раскрывались при выходе произведений. '
            'Продолжить всё равно?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ПОРЯДОК ВЫХОДА'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('ПРОДОЛЖИТЬ'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    setState(() => _order = FranchiseViewingOrder.chronology);
  }

  @override
  Widget build(BuildContext context) {
    final ordered = MediaSearchService.orderFranchiseItems(_items, _order);
    final heading = widget.name.isEmpty
        ? 'ФРАНШИЗА'
        : widget.name.toUpperCase();
    final note = switch (_order) {
      FranchiseViewingOrder.release => 'Порядок выхода',
      FranchiseViewingOrder.chronology when _hasVerifiedChronology =>
        'Хронология событий · подтверждённые данные',
      FranchiseViewingOrder.chronology => 'Хронология пока не подтверждена',
      FranchiseViewingOrder.smart when _isResolvingChronology =>
        'Проверяем источники и собираем хронологию…',
      FranchiseViewingOrder.smart
          when _hasVerifiedChronology &&
              !_items.any((entry) => entry.chronologySpoilerRisk) =>
        'Умный порядок · без известных сюжетных спойлеров',
      FranchiseViewingOrder.smart =>
        'Умный порядок пока использует порядок выхода: хронология и риск спойлеров не подтверждены',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _Label(heading),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              key: const ValueKey('franchise-order-release'),
              label: const Text('По выходу'),
              selected: _order == FranchiseViewingOrder.release,
              onSelected: (_) =>
                  setState(() => _order = FranchiseViewingOrder.release),
            ),
            ChoiceChip(
              key: const ValueKey('franchise-order-chronology'),
              label: const Text('По сюжету'),
              selected: _order == FranchiseViewingOrder.chronology,
              onSelected: (_) => _selectChronology(),
            ),
            ChoiceChip(
              key: const ValueKey('franchise-order-smart'),
              label: const Text('Умный порядок'),
              selected: _order == FranchiseViewingOrder.smart,
              onSelected: (_) =>
                  setState(() => _order = FranchiseViewingOrder.smart),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(note, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 10),
        SizedBox(
          height: 184,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: ordered.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final related = ordered[index];
              final year = related.releaseDate.length >= 4
                  ? related.releaseDate.substring(0, 4)
                  : '';
              return SizedBox(
                width: 104,
                child: InkWell(
                  key: ValueKey('franchise-film-${related.id}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MediaDetailsPage(
                        item: MediaItem(
                          id: related.id,
                          title: related.title,
                          type: 'Фильм',
                          posterUrl: related.posterUrl,
                          rating: 0,
                          voiceovers: const [],
                          videoUrl: '',
                          description: related.overview,
                        ),
                        searchService: widget.searchService,
                        preferences: widget.preferences,
                        playerFactory: widget.playerFactory,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: related.posterUrl.isEmpty
                            ? Container(
                                width: 104,
                                height: 132,
                                color: SystemCorePalette.panel,
                                child: const Icon(
                                  Icons.movie_outlined,
                                  color: SystemCorePalette.muted,
                                ),
                              )
                            : Image.network(
                                related.posterUrl,
                                width: 104,
                                height: 132,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 104,
                                  height: 132,
                                  color: SystemCorePalette.panel,
                                  child: const Icon(
                                    Icons.movie_outlined,
                                    color: SystemCorePalette.muted,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        related.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (year.isNotEmpty)
                        Text(
                          year,
                          style: const TextStyle(
                            color: SystemCorePalette.muted,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
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

class _MediaSourceDialog extends StatefulWidget {
  const _MediaSourceDialog({this.episodeNumber});

  final int? episodeNumber;

  @override
  State<_MediaSourceDialog> createState() => _MediaSourceDialogState();
}

class _MediaSourceDialogState extends State<_MediaSourceDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: SystemCorePalette.panel,
    title: Text(
      widget.episodeNumber == null
          ? 'Источник видео'
          : 'Источник серии ${widget.episodeNumber}',
      style: const TextStyle(color: Colors.white),
    ),
    content: TextField(
      controller: _controller,
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
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('ОТМЕНА'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: const Text('ОТКРЫТЬ'),
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
  final raw = await showDialog<String>(
    context: context,
    builder: (_) => _MediaSourceDialog(episodeNumber: episode?.episodeNumber),
  );
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

Future<void> _openProvider(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
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
