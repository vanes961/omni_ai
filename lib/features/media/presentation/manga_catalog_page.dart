import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:omni_ai/features/media/data/manga_reading_progress_repository.dart';
import 'package:omni_ai/features/media/presentation/manga_reader_progress_overlay.dart';
import 'package:omni_ai/features/media/services/manga_catalog_service.dart';
import 'package:omni_ai/features/media/services/manga_chapter_service.dart';

class MangaCatalogPage extends StatefulWidget {
  const MangaCatalogPage({super.key, this.catalogService, this.chapterService});

  final MangaCatalogService? catalogService;
  final MangaChapterService? chapterService;

  @override
  State<MangaCatalogPage> createState() => _MangaCatalogPageState();
}

class _MangaCatalogPageState extends State<MangaCatalogPage> {
  late final MangaCatalogService _catalog =
      widget.catalogService ?? MangaCatalogService();
  final _query = TextEditingController();
  List<MangaCatalogItem> _results = const [];
  bool _loading = false;
  String? _error;

  Future<void> _search([String? value]) async {
    final query = (value ?? _query.text).trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _catalog.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Не удалось загрузить каталог. Проверьте подключение и повторите поиск.';
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    if (widget.catalogService == null) _catalog.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF080D0A),
    appBar: AppBar(
      title: const Text('МАНГА'),
      backgroundColor: const Color(0xFF111714),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Название манги',
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF74D69A)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward, color: Color(0xFF74D69A)),
                onPressed: _search,
              ),
              filled: true,
              fillColor: const Color(0xFF111714),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(color: Color(0xFF74D69A)),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: const TextStyle(color: Colors.white70)),
          ),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Text(
                    _loading
                        ? 'Ищем мангу…'
                        : 'Найдите мангу в каталоге MangaDex',
                    style: const TextStyle(color: Colors.white60),
                  ),
                )
              : ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final manga = _results[index];
                    return ListTile(
                      key: ValueKey('manga-catalog-${manga.id}'),
                      leading: SizedBox(
                        width: 54,
                        height: 76,
                        child: manga.coverUrl.isEmpty
                            ? const Icon(
                                Icons.menu_book,
                                color: Color(0xFF74D69A),
                              )
                            : CachedNetworkImage(
                                imageUrl: manga.coverUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => const Icon(
                                  Icons.menu_book,
                                  color: Color(0xFF74D69A),
                                ),
                              ),
                      ),
                      title: Text(
                        manga.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        [
                          if (manga.authors.isNotEmpty)
                            manga.authors.join(', '),
                          if (manga.status.isNotEmpty) manga.status,
                        ].join(' • '),
                        style: const TextStyle(color: Colors.white60),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Color(0xFF74D69A),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MangaReaderPage(
                            manga: manga,
                            chapterService: widget.chapterService,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        const Padding(
          padding: EdgeInsets.all(10),
          child: Text(
            'Каталог и главы предоставлены MangaDex • доступны только русские переводы',
            style: TextStyle(color: Colors.white38, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );
}

class MangaReaderPage extends StatefulWidget {
  const MangaReaderPage({required this.manga, this.chapterService, super.key});
  final MangaCatalogItem manga;
  final MangaChapterService? chapterService;

  @override
  State<MangaReaderPage> createState() => _MangaReaderPageState();
}

class _MangaReaderPageState extends State<MangaReaderPage> {
  late final MangaChapterService _service =
      widget.chapterService ?? MangaChapterService();
  final MangaReadingProgressRepository _progress =
      MangaReadingProgressRepository();
  final ScrollController _scroll = ScrollController();
  List<MangaChapterOption> _chapters = const [];
  final List<Uri> _pages = [];
  final Set<int> _loadedChapterIndexes = <int>{};
  final Map<int, int> _chapterStartPages = <int, int>{};
  int _chapterIndex = 0;
  int _pageIndex = 0;
  bool _loadingChapters = true;
  bool _loadingPages = false;
  bool _loadingNext = false;
  bool _restoring = false;
  String? _error;
  String? _pageError;
  bool _hasMoreChapters = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadChapters();
  }

  Future<void> _loadChapters() async {
    setState(() {
      _loadingChapters = true;
      _error = null;
    });
    try {
      final all = <MangaChapterOption>[];
      var offset = 0;
      while (offset < 500) {
        final batch = await _service.fetchRussianChapters(
          widget.manga.id,
          offset: offset,
          limit: 100,
        );
        all.addAll(batch);
        if (batch.length < 100) break;
        offset += batch.length;
      }
      if (!mounted) return;
      if (all.isEmpty) {
        setState(() {
          _chapters = const [];
          _loadingChapters = false;
          _error =
              'Русские главы пока не найдены. Английские главы не подставляются вместо перевода.';
        });
        return;
      }
      final saved = await _progress.getById(widget.manga.canonicalId);
      var initial = 0;
      if (saved != null) {
        final found = all.indexWhere((c) => c.chapter == saved.chapterLabel);
        if (found >= 0) initial = found;
      }
      setState(() {
        _chapters = all;
        _chapterIndex = initial;
        _loadingChapters = false;
        _hasMoreChapters = all.length >= 500;
      });
      await _loadChapterPages(initial, restore: saved);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingChapters = false;
        _error = 'Не удалось загрузить русские главы: $e';
      });
    }
  }

  Future<void> _loadChapterPages(
    int index, {
    MangaReadingProgress? restore,
  }) async {
    if (index < 0 || index >= _chapters.length || _loadingPages) return;
    setState(() {
      _loadingPages = true;
      _pageError = null;
      _chapterIndex = index;
    });
    try {
      final manifest = await _service.fetchPages(_chapters[index].id);
      if (!mounted) return;
      if (manifest == null || manifest.imageUrls.isEmpty) {
        setState(() {
          _loadingPages = false;
          _pageError = 'Страницы этой главы недоступны.';
        });
        return;
      }
      setState(() {
        _pages
          ..clear()
          ..addAll(manifest.imageUrls);
        _loadedChapterIndexes
          ..clear()
          ..add(index);
        _chapterStartPages
          ..clear()
          ..[index] = 0;
        _pageIndex = restore?.page == null
            ? 0
            : (restore!.page! - 1).clamp(0, manifest.imageUrls.length - 1);
        _loadingPages = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _restoring = true;
        final target =
            _pageIndex * MediaQuery.sizeOf(context).height * 0.82 +
            (restore?.pageOffset ?? 0) *
                MediaQuery.sizeOf(context).height *
                0.82;
        _scroll.jumpTo(
          target.clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
        );
        _restoring = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPages = false;
        _pageError = 'Не удалось загрузить страницы: $e';
      });
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients || _restoring) return;
    final extent = MediaQuery.sizeOf(context).height * 0.82;
    final page = (_scroll.offset / extent)
        .floor()
        .clamp(0, (_pages.length - 1).clamp(0, 1 << 30))
        .toInt();
    if (_pages.isNotEmpty) {
      var visibleChapter = _chapterIndex;
      for (final entry in _chapterStartPages.entries) {
        if (entry.value <= page &&
            entry.value >= (_chapterStartPages[visibleChapter] ?? 0))
          visibleChapter = entry.key;
      }
      _chapterIndex = visibleChapter;
      _pageIndex = page - (_chapterStartPages[_chapterIndex] ?? 0);
      _saveProgress();
    }
    if (_scroll.position.maxScrollExtent - _scroll.position.pixels <
        extent * 2) {
      _loadNextChapter();
    }
  }

  Future<void> _saveProgress() async {
    if (_chapters.isEmpty) return;
    final pageOffset =
        ((_scroll.hasClients
                    ? _scroll.offset %
                          (MediaQuery.sizeOf(context).height * 0.82)
                    : 0) /
                (MediaQuery.sizeOf(context).height * 0.82))
            .clamp(0.0, 1.0)
            .toDouble();
    try {
      await _progress.save(
        MangaReadingProgress(
          mangaId: widget.manga.canonicalId,
          chapterIndex: _chapterIndex,
          chapterLabel: _chapters[_chapterIndex].chapter,
          page: _pageIndex + 1,
          pageOffset: pageOffset,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } on Object {
      // Reading remains usable if local progress storage is temporarily unavailable.
    }
  }

  Future<void> _loadNextChapter() async {
    if (_loadingNext || _loadingPages || !_hasMoreChapters) return;
    final nextIndex = List<int>.generate(
      _chapters.length,
      (i) => i,
    ).firstWhere((i) => !_loadedChapterIndexes.contains(i), orElse: () => -1);
    if (nextIndex < 0) {
      _hasMoreChapters = false;
      return;
    }
    _loadingNext = true;
    try {
      final manifest = await _service.fetchPages(_chapters[nextIndex].id);
      if (!mounted) return;
      if (manifest != null && manifest.imageUrls.isNotEmpty) {
        setState(() {
          _chapterStartPages[nextIndex] = _pages.length;
          _pages.addAll(manifest.imageUrls);
          _loadedChapterIndexes.add(nextIndex);
          if (_loadedChapterIndexes.length >= _chapters.length)
            _hasMoreChapters = false;
        });
      } else {
        _loadedChapterIndexes.add(nextIndex);
      }
    } on Object {
      // A failed prefetch is retried on the next near-end scroll.
    } finally {
      _loadingNext = false;
    }
  }

  Future<void> _pickChapter(MangaReaderChapterOption option) async {
    final index = _chapters.indexWhere((c) => c.id == option.id);
    if (index < 0) return;
    setState(() {
      _pages.clear();
      _pageIndex = 0;
      _chapterIndex = index;
      _pageError = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _loadChapterPages(index);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    if (widget.chapterService == null) _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: const Color(0xFF111714),
      title: Text(
        widget.manga.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          tooltip: 'Открыть источник MangaDex',
          onPressed: () {},
          icon: const Icon(Icons.menu_book, color: Color(0xFF74D69A)),
        ),
      ],
    ),
    body: _loadingChapters
        ? const Center(
            child: CircularProgressIndicator(color: Color(0xFF74D69A)),
          )
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          )
        : Stack(
            children: [
              if (_pages.isNotEmpty)
                ListView.builder(
                  controller: _scroll,
                  cacheExtent: MediaQuery.sizeOf(context).height * 1.5,
                  itemCount: _pages.length + (_loadingNext ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _pages.length)
                      return const Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF74D69A),
                          ),
                        ),
                      );
                    return CachedNetworkImage(
                      imageUrl: _pages[index].toString(),
                      fit: BoxFit.fitWidth,
                      width: double.infinity,
                      placeholder: (_, _) => const SizedBox(
                        height: 220,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF74D69A),
                          ),
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        height: 180,
                        alignment: Alignment.center,
                        color: const Color(0xFF111714),
                        child: const Text(
                          'Страница не загрузилась',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    );
                  },
                )
              else if (_pageError != null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _pageError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => _loadChapterPages(_chapterIndex),
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                )
              else
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFF74D69A)),
                ),
              if (_chapters.isNotEmpty)
                MangaReaderProgressOverlay(
                  chapterLabel: _chapters[_chapterIndex].displayLabel,
                  currentPage: _pageIndex + 1,
                  totalPages: _pages.length,
                  chapters: [
                    for (final c in _chapters)
                      MangaReaderChapterOption(
                        id: c.id,
                        label: c.displayLabel,
                        title: c.title,
                      ),
                  ],
                  onChapterSelected: _pickChapter,
                ),
            ],
          ),
  );
}
import 'package:flutter/material.dart';

/// Compact chapter selector and progress overlay for a continuous manga reader.
///
/// Place it in the reader's [Stack]. [chapters] should contain the complete
/// chapter list in reading order and use stable IDs across refreshes.
class MangaReaderProgressOverlay extends StatelessWidget {
  const MangaReaderProgressOverlay({
    required this.chapterLabel,
    required this.currentPage,
    required this.totalPages,
    this.chapters = const [],
    this.onChapterSelected,
    super.key,
  });

  final String chapterLabel;
  final int currentPage;
  final int totalPages;
  final List<MangaReaderChapterOption> chapters;
  final ValueChanged<MangaReaderChapterOption>? onChapterSelected;

  int get _safeTotalPages => totalPages < 0 ? 0 : totalPages;

  int get _safeCurrentPage {
    if (_safeTotalPages == 0) return 0;
    return currentPage.clamp(1, _safeTotalPages);
  }

  double? get _progress => _safeTotalPages == 0
      ? null
      : (_safeCurrentPage / _safeTotalPages).clamp(0.0, 1.0).toDouble();

  Future<void> _openChapterPicker(BuildContext context) async {
    if (chapters.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111714),
      builder: (sheetContext) => _ChapterPickerSheet(
        chapters: chapters,
        currentChapterLabel: chapterLabel,
        onSelected: (chapter) {
          Navigator.of(sheetContext).pop();
          onChapterSelected?.call(chapter);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chapter = chapterLabel.trim();
    final chapterText = chapter.isEmpty ? 'Чтение' : 'Гл. $chapter';

    return Positioned(
      top: 8,
      right: 8,
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 142),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xE6111714),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x6674D69A), width: 0.7),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      key: const ValueKey('manga-reader-chapter-picker'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: chapters.isEmpty
                          ? null
                          : () => _openChapterPicker(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.menu_book_rounded,
                              size: 13,
                              color: Color(0xFF9BE6B4),
                            ),
                            const SizedBox(width: 4),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 94),
                              child: Text(
                                chapterText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFF1F7F2),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (chapters.isNotEmpty) ...[
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.expand_more_rounded,
                                size: 14,
                                color: Color(0xFFB9C9BE),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_safeTotalPages > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    '$_safeCurrentPage/$_safeTotalPages',
                    style: const TextStyle(
                      color: Color(0xFFB9C9BE),
                      fontSize: 9,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                if (_safeTotalPages > 0) ...[
                  const SizedBox(height: 5),
                  SizedBox(
                    width: 116,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 2,
                        backgroundColor: const Color(0xFF354139),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF74D69A),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MangaReaderChapterOption {
  const MangaReaderChapterOption({
    required this.id,
    required this.label,
    this.title,
  });

  final String id;
  final String label;
  final String? title;
}

class _ChapterPickerSheet extends StatelessWidget {
  const _ChapterPickerSheet({
    required this.chapters,
    required this.currentChapterLabel,
    required this.onSelected,
  });

  final List<MangaReaderChapterOption> chapters;
  final String currentChapterLabel;
  final ValueChanged<MangaReaderChapterOption> onSelected;

  @override
  Widget build(BuildContext context) {
    final currentLabel = currentChapterLabel.trim();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 34,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF526057),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                const Icon(Icons.menu_book_rounded, color: Color(0xFF9BE6B4)),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Все главы',
                    style: TextStyle(
                      color: Color(0xFFF1F7F2),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${chapters.length}',
                  style: const TextStyle(
                    color: Color(0xFFB9C9BE),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF29332D)),
          Expanded(
            child: ListView.builder(
              key: const ValueKey('manga-reader-chapter-list'),
              itemCount: chapters.length,
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                final isCurrent = chapter.label.trim() == currentLabel;

                return ListTile(
                  key: ValueKey('manga-chapter-${chapter.id}'),
                  dense: true,
                  title: Text(
                    'Глава ${chapter.label}',
                    style: TextStyle(
                      color: isCurrent
                          ? const Color(0xFF9BE6B4)
                          : const Color(0xFFF1F7F2),
                      fontSize: 14,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  subtitle:
                      chapter.title == null || chapter.title!.trim().isEmpty
                      ? null
                      : Text(
                          chapter.title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF9CAAA0),
                            fontSize: 12,
                          ),
                        ),
                  trailing: isCurrent
                      ? const Icon(
                          Icons.play_arrow_rounded,
                          color: Color(0xFF74D69A),
                        )
                      : null,
                  onTap: () => onSelected(chapter),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/core/network/widgets/network_image_with_fallback.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/favorites/data/favorite_item.dart';
import 'package:omni_ai/features/favorites/data/favorites_repository.dart';
import 'package:omni_ai/features/favorites/presentation/favorites_page.dart';
import 'package:omni_ai/features/favorites/services/favorite_interest_analytics.dart';
import 'package:omni_ai/features/media/presentation/player_page.dart';
