import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:omni_ai/features/media/data/manga_reading_progress_repository.dart';
import 'package:omni_ai/features/media/presentation/manga_reader_progress_overlay.dart';
import 'package:omni_ai/features/media/services/manga_catalog_service.dart';
import 'package:omni_ai/features/media/services/manga_chapter_service.dart';
import 'package:url_launcher/url_launcher.dart';

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
  int _searchGeneration = 0;
  String? _error;

  Future<void> _search([String? value]) async {
    final generation = ++_searchGeneration;
    final query = (value ?? _query.text).trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
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
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } on Object {
      if (!mounted || generation != _searchGeneration) return;
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
  final GlobalKey _viewportKey = GlobalKey();
  final Map<int, GlobalKey> _pageKeys = <int, GlobalKey>{};
  Timer? _saveDebounce;
  List<MangaChapterOption> _chapters = const [];
  final List<Uri> _pages = [];
  final Set<int> _loadedChapterIndexes = <int>{};
  final Map<int, int> _chapterStartPages = <int, int>{};
  int _chapterIndex = 0;
  int _pageIndex = 0;
  bool _loadingChapters = true;
  bool _loadingPages = false;
  bool _loadingNext = false;
  bool _loadingPrevious = false;
  bool _restoring = false;
  String? _error;
  String? _pageError;
  bool _hasMoreChapters = true;
  bool _loadingMoreChapters = false;
  int _nextChapterOffset = 0;
  int _readerGeneration = 0;
  double _viewportExtent = 1;
  Size? _lastViewportSize;
  bool _geometryRestoreScheduled = false;
  double _pageOffset = 0;

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
      var hasMore = true;
      while (offset < 500) {
        final batch = await _service.fetchRussianChapters(
          widget.manga.id,
          offset: offset,
          limit: 100,
        );
        all.addAll(batch);
        offset += 100;
        if (batch.length < 100) {
          hasMore = false;
          break;
        }
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
        _nextChapterOffset = offset;
        _hasMoreChapters = hasMore;
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

  Future<void> _loadMoreChapterOptions() async {
    if (_loadingMoreChapters || !_hasMoreChapters) return;
    _loadingMoreChapters = true;
    final generation = _readerGeneration;
    try {
      final batch = await _service.fetchRussianChapters(
        widget.manga.id,
        offset: _nextChapterOffset,
        limit: 100,
      );
      if (!mounted || generation != _readerGeneration) return;

      final knownIds = _chapters.map((chapter) => chapter.id).toSet();
      final additions = batch
          .where((chapter) => knownIds.add(chapter.id))
          .toList();
      if (additions.isNotEmpty) {
        setState(() => _chapters.addAll(additions));
      }
      _nextChapterOffset += 100;
      if (batch.length < 100 || additions.isEmpty) {
        _hasMoreChapters = false;
      }
    } on Object {
      // Keep the current reader usable; the next near-end scroll retries.
    } finally {
      _loadingMoreChapters = false;
    }
  }

  Future<void> _loadChapterPages(
    int index, {
    MangaReadingProgress? restore,
  }) async {
    if (index < 0 || index >= _chapters.length || _loadingPages) return;
    final generation = _readerGeneration;
    setState(() {
      _loadingPages = true;
      _pageError = null;
      _chapterIndex = index;
    });
    try {
      final manifest = await _service.fetchPages(_chapters[index].id);
      if (!mounted || generation != _readerGeneration) return;
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
        _pageOffset = restore?.pageOffset ?? 0;
        _pageKeys.clear();
        _loadingPages = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _restoring = true;
        final extent = _viewportExtent > 0 ? _viewportExtent : 1.0;
        final target =
            _pageIndex * extent + (restore?.pageOffset ?? 0) * extent;
        _scroll.jumpTo(
          target.clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scroll.hasClients) return;
          final pageContext = _pageKeys[_pageIndex]?.currentContext;
          final pageObject = pageContext?.findRenderObject();
          final viewportObject = _viewportKey.currentContext
              ?.findRenderObject();
          if (pageObject is RenderBox &&
              pageObject.hasSize &&
              viewportObject is RenderBox &&
              viewportObject.hasSize) {
            final top = pageObject
                .localToGlobal(Offset.zero, ancestor: viewportObject)
                .dy;
            final corrected =
                _scroll.offset + top + (_pageOffset * pageObject.size.height);
            _scroll.jumpTo(
              corrected.clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
            );
          }
          _restoring = false;
        });
      });
    } on Object catch (e) {
      if (!mounted || generation != _readerGeneration) return;
      setState(() {
        _loadingPages = false;
        _pageError = 'Не удалось загрузить страницы: $e';
      });
    }
  }

  bool _syncVisiblePage({bool scheduleSave = true}) {
    final viewportObject = _viewportKey.currentContext?.findRenderObject();
    if (viewportObject is! RenderBox || !viewportObject.hasSize) return false;

    _pageKeys.removeWhere((_, key) => key.currentContext == null);
    var visibleIndex = -1;
    var visibleTop = double.infinity;
    var visibleHeight = 0.0;
    for (final entry in _pageKeys.entries) {
      final pageObject = entry.value.currentContext?.findRenderObject();
      if (pageObject is! RenderBox || !pageObject.hasSize) continue;
      final top = pageObject
          .localToGlobal(Offset.zero, ancestor: viewportObject)
          .dy;
      final bottom = top + pageObject.size.height;
      if (bottom > 0 && top < viewportObject.size.height && top < visibleTop) {
        visibleIndex = entry.key;
        visibleTop = top;
        visibleHeight = pageObject.size.height;
      }
    }
    if (visibleIndex < 0 || visibleHeight <= 0) return false;

    var visibleChapter = _chapterIndex;
    var latestStartPage = -1;
    for (final entry in _chapterStartPages.entries) {
      if (entry.value <= visibleIndex && entry.value > latestStartPage) {
        visibleChapter = entry.key;
        latestStartPage = entry.value;
      }
    }
    final nextPageIndex =
        visibleIndex - (_chapterStartPages[visibleChapter] ?? 0);
    final nextOffset = ((-visibleTop) / visibleHeight)
        .clamp(0.0, 1.0)
        .toDouble();
    final pageChanged =
        visibleChapter != _chapterIndex || nextPageIndex != _pageIndex;
    final offsetChanged = (nextOffset - _pageOffset).abs() >= 0.15;
    _chapterIndex = visibleChapter;
    _pageIndex = nextPageIndex;
    _pageOffset = nextOffset;
    if (scheduleSave && (pageChanged || offsetChanged)) _scheduleProgressSave();
    return true;
  }

  void _scheduleGeometryRestore(Size nextSize) {
    final previousSize = _lastViewportSize;
    _lastViewportSize = nextSize;
    if (previousSize == null ||
        previousSize == nextSize ||
        _geometryRestoreScheduled ||
        _pages.isEmpty) {
      return;
    }

    // Keep the same fractional position inside the visible page when a phone
    // rotates or a foldable changes its available viewport dimensions.
    final generationAtResize = _readerGeneration;
    final chapterAtResize = _chapterIndex;
    final localPageAtResize = _pageIndex;
    final offsetAtResize = _pageOffset;
    final globalPageAtResize =
        (_chapterStartPages[chapterAtResize] ?? 0) + localPageAtResize;
    _geometryRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geometryRestoreScheduled = false;
      if (!mounted ||
          generationAtResize != _readerGeneration ||
          !_scroll.hasClients ||
          _pages.isEmpty) {
        return;
      }
      final pageContext = _pageKeys[globalPageAtResize]?.currentContext;
      final pageObject = pageContext?.findRenderObject();
      final viewportObject = _viewportKey.currentContext?.findRenderObject();
      if (pageObject is! RenderBox ||
          !pageObject.hasSize ||
          viewportObject is! RenderBox ||
          !viewportObject.hasSize) {
        return;
      }
      _restoring = true;
      final top = pageObject
          .localToGlobal(Offset.zero, ancestor: viewportObject)
          .dy;
      final corrected =
          _scroll.offset +
          top +
          (offsetAtResize.clamp(0.0, 1.0) * pageObject.size.height);
      _scroll.jumpTo(
        corrected.clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
      );
      _chapterIndex = chapterAtResize;
      _pageIndex = localPageAtResize;
      _pageOffset = offsetAtResize;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generationAtResize == _readerGeneration) {
          _restoring = false;
        }
      });
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients || _restoring) return;
    final extent = _viewportExtent > 0 ? _viewportExtent : 1.0;
    if (!_syncVisiblePage()) {
      final page = (_scroll.offset / extent)
          .floor()
          .clamp(0, (_pages.length - 1).clamp(0, 1 << 30))
          .toInt();
      var visibleChapter = _chapterIndex;
      var latestStartPage = -1;
      for (final entry in _chapterStartPages.entries) {
        if (entry.value <= page && entry.value > latestStartPage) {
          visibleChapter = entry.key;
          latestStartPage = entry.value;
        }
      }
      final nextPageIndex = page - (_chapterStartPages[visibleChapter] ?? 0);
      if (visibleChapter != _chapterIndex || nextPageIndex != _pageIndex) {
        _chapterIndex = visibleChapter;
        _pageIndex = nextPageIndex;
        _pageOffset = (_scroll.offset % extent / extent).clamp(0.0, 1.0);
        _scheduleProgressSave();
      }
    }
    if (_scroll.position.maxScrollExtent - _scroll.position.pixels <
        extent * 2) {
      _loadNextChapter();
    }
    if (_scroll.position.pixels < extent * 1.5) {
      _loadPreviousChapter();
    }
  }

  void _scheduleProgressSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _saveProgress();
    });
  }

  MangaReadingProgress? _captureProgress({bool measureVisible = true}) {
    if (_chapters.isEmpty ||
        _chapterIndex < 0 ||
        _chapterIndex >= _chapters.length) {
      return null;
    }
    if (measureVisible) _syncVisiblePage(scheduleSave: false);
    return MangaReadingProgress(
      mangaId: widget.manga.canonicalId,
      chapterIndex: _chapterIndex,
      chapterLabel: _chapters[_chapterIndex].chapter,
      page: _pageIndex + 1,
      pageOffset: _pageOffset,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> _saveProgress() async {
    final progress = _captureProgress();
    if (progress == null) return;
    try {
      await _progress.save(progress);
    } on Object {
      // Reading remains usable if local progress storage is temporarily unavailable.
    }
  }

  Future<void> _loadNextChapter() async {
    if (_loadingNext || _loadingPages) return;
    var nextIndex = _chapterIndex + 1;
    while (nextIndex < _chapters.length &&
        _loadedChapterIndexes.contains(nextIndex)) {
      nextIndex++;
    }
    if (nextIndex >= _chapters.length) {
      if (!_hasMoreChapters) return;
      final previousLength = _chapters.length;
      await _loadMoreChapterOptions();
      if (!mounted || _chapters.length == previousLength) return;
      nextIndex = _chapterIndex + 1;
      while (nextIndex < _chapters.length &&
          _loadedChapterIndexes.contains(nextIndex)) {
        nextIndex++;
      }
      if (nextIndex >= _chapters.length) return;
    }
    _loadingNext = true;
    final generation = _readerGeneration;
    try {
      final manifest = await _service.fetchPages(_chapters[nextIndex].id);
      if (!mounted || generation != _readerGeneration) return;
      if (manifest != null && manifest.imageUrls.isNotEmpty) {
        setState(() {
          _chapterStartPages[nextIndex] = _pages.length;
          _pages.addAll(manifest.imageUrls);
          _loadedChapterIndexes.add(nextIndex);
          if (_loadedChapterIndexes.length >= _chapters.length) {
            _hasMoreChapters = false;
          }
        });
      } else {
        _loadedChapterIndexes.add(nextIndex);
      }
    } on Object {
      // A failed prefetch is retried on the next near-end scroll.
    } finally {
      if (generation == _readerGeneration) _loadingNext = false;
    }
  }

  Future<void> _loadPreviousChapter() async {
    if (_loadingPrevious ||
        _loadingPages ||
        !_scroll.hasClients ||
        _pages.isEmpty ||
        _loadedChapterIndexes.isEmpty) {
      return;
    }

    final firstLoadedIndex = _loadedChapterIndexes.reduce(
      (a, b) => a < b ? a : b,
    );
    final previousIndex = firstLoadedIndex - 1;
    if (previousIndex < 0) return;

    final generation = _readerGeneration;
    _loadingPrevious = true;
    try {
      final manifest = await _service.fetchPages(_chapters[previousIndex].id);
      if (!mounted || generation != _readerGeneration) return;
      final previousPages = manifest?.imageUrls ?? const <Uri>[];
      if (previousPages.isEmpty) {
        _loadedChapterIndexes.add(previousIndex);
        return;
      }

      // Measure the anchor after the network wait, so scrolling while the
      // request is in flight does not restore an obsolete position.
      if (!_scroll.hasClients) return;
      final viewportObject = _viewportKey.currentContext?.findRenderObject();
      if (viewportObject is! RenderBox || !viewportObject.hasSize) return;

      GlobalKey? anchorKey;
      double? anchorTop;
      for (final entry in _pageKeys.entries) {
        final pageObject = entry.value.currentContext?.findRenderObject();
        if (pageObject is! RenderBox || !pageObject.hasSize) continue;
        final top = pageObject
            .localToGlobal(Offset.zero, ancestor: viewportObject)
            .dy;
        if (top + pageObject.size.height > 0 &&
            top < viewportObject.size.height) {
          anchorKey = entry.value;
          anchorTop = top;
          break;
        }
      }
      if (anchorKey == null || anchorTop == null) return;

      final oldOffset = _scroll.offset;
      final count = previousPages.length;
      // Suppress scroll-driven progress updates while the prepended layout is
      // settling; otherwise the temporary offset can overwrite saved progress.
      _restoring = true;
      setState(() {
        final shiftedKeys = <int, GlobalKey>{};
        for (final entry in _pageKeys.entries) {
          shiftedKeys[entry.key + count] = entry.value;
        }
        _pageKeys
          ..clear()
          ..addAll(shiftedKeys);

        for (final entry in _chapterStartPages.entries.toList()) {
          _chapterStartPages[entry.key] = entry.value + count;
        }
        _chapterStartPages[previousIndex] = 0;
        _pages.insertAll(0, previousPages);
        _loadedChapterIndexes.add(previousIndex);
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _readerGeneration) return;
        if (!_scroll.hasClients) {
          _restoring = false;
          return;
        }
        final updatedViewport = _viewportKey.currentContext?.findRenderObject();
        final anchorObject = anchorKey?.currentContext?.findRenderObject();
        if (updatedViewport is! RenderBox ||
            !updatedViewport.hasSize ||
            anchorObject is! RenderBox ||
            !anchorObject.hasSize) {
          _restoring = false;
          return;
        }
        final newTop = anchorObject
            .localToGlobal(Offset.zero, ancestor: updatedViewport)
            .dy;
        final corrected = oldOffset + (newTop - anchorTop!);
        _scroll.jumpTo(
          corrected.clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _readerGeneration) return;
          _restoring = false;
          _syncVisiblePage();
        });
      });
    } on Object {
      // Retry when the reader returns to the start of the loaded content.
    } finally {
      if (generation == _readerGeneration) _loadingPrevious = false;
    }
  }

  Future<void> _pickChapter(MangaReaderChapterOption option) async {
    final index = _chapters.indexWhere((c) => c.id == option.id);
    if (index < 0) return;
    _saveDebounce?.cancel();

    // Capture and start saving the old position before invalidating its pending
    // requests. Do not await here: a slow local write must not let an old page
    // prefetch append to the reader after the user has chosen another chapter.
    final saveFuture = _saveProgress();
    final generation = ++_readerGeneration;
    _pageKeys.clear();
    setState(() {
      _pages.clear();
      _loadedChapterIndexes.clear();
      _chapterStartPages.clear();
      _pageIndex = 0;
      _pageOffset = 0;
      _chapterIndex = index;
      _loadingPages = false;
      _loadingNext = false;
      _loadingPrevious = false;
      // A pending post-frame geometry callback from the old chapter must not
      // leave scroll/progress synchronization disabled for the new selection.
      _restoring = false;
      _pageError = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);

    await saveFuture;
    if (!mounted || generation != _readerGeneration) return;
    await _loadChapterPages(index);
  }

  Future<void> _openSource() async {
    final uri = Uri.tryParse(widget.manga.sourceUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'mangadex.org' ||
        !uri.path.startsWith('/title/')) {
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть MangaDex.')),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть MangaDex.')),
        );
      }
    }
  }

  Future<void> _retryPageImage(Uri uri) async {
    try {
      await CachedNetworkImage.evictFromCache(uri.toString());
    } on Object {
      // A rebuild still gives the image provider another chance to load.
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    final progress = _captureProgress(measureVisible: false);
    if (progress != null) {
      unawaited(_progress.save(progress).catchError((Object _) {}));
    }
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    if (widget.chapterService == null) _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            onPressed: _openSource,
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
          : LayoutBuilder(
              builder: (context, constraints) {
                _viewportExtent = constraints.maxHeight;
                _scheduleGeometryRestore(constraints.biggest);
                return Stack(
                  children: [
                    if (_pages.isNotEmpty)
                      Positioned.fill(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 900),
                            child: ListView.builder(
                              key: _viewportKey,
                              controller: _scroll,
                              itemCount: _pages.length + (_loadingNext ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= _pages.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(28),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF74D69A),
                                      ),
                                    ),
                                  );
                                }
                                return KeyedSubtree(
                                  key: _pageKeys.putIfAbsent(
                                    index,
                                    GlobalKey.new,
                                  ),
                                  child: CachedNetworkImage(
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
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            'Страница не загрузилась',
                                            style: TextStyle(
                                              color: Colors.white70,
                                            ),
                                          ),
                                          TextButton.icon(
                                            onPressed: () =>
                                                _retryPageImage(_pages[index]),
                                            icon: const Icon(
                                              Icons.refresh,
                                              size: 18,
                                            ),
                                            label: const Text('Повторить'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
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
                        child: CircularProgressIndicator(
                          color: Color(0xFF74D69A),
                        ),
                      ),
                    if (_chapters.isNotEmpty)
                      MangaReaderProgressOverlay(
                        chapterLabel: _chapters[_chapterIndex].displayLabel,
                        currentPage: _pageIndex + 1,
                        totalPages: _chapters[_chapterIndex].pageCount,
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
                );
              },
            ),
    );
  }
}
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/diagnostics/diagnostic_report.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:omni_ai/features/news/data/news_interest_repository.dart';
import 'package:omni_ai/features/news/data/shared_preferences_news_cache.dart';
import 'package:omni_ai/features/news/data/news_feedback_repository.dart';
import 'package:omni_ai/features/news/data/shared_preferences_news_interest_repository.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';
import 'package:omni_ai/features/news/models/news_article.dart';
import 'package:omni_ai/features/favorites/data/favorite_item.dart';
import 'package:omni_ai/features/favorites/data/favorites_repository.dart';
import 'package:omni_ai/features/favorites/data/interest_feedback_repository.dart';
import 'package:omni_ai/features/favorites/services/favorite_interest_analytics.dart';
import 'package:omni_ai/features/news/services/news_rss_service.dart';
import 'package:omni_ai/features/news/services/news_digest_service.dart';
import 'package:omni_ai/features/news/services/news_source_localization_service.dart';
import 'package:omni_ai/features/news/services/news_reminder_service.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

class NewsCenterPage extends StatefulWidget {
  const NewsCenterPage({
    super.key,
    this.repository,
    this.aiEngine,
    this.newsService,
    this.newsCache,
    this.legacyPreferences,
    this.preferencesStore,
  });

  final NewsInterestRepository? repository;
  final AIEngine? aiEngine;
  final NewsRssService? newsService;
  final SharedPreferencesNewsCache? newsCache;
  final UserPreferences? legacyPreferences;
  final UserPreferencesStore? preferencesStore;

  @override
  State<NewsCenterPage> createState() => _NewsCenterPageState();
}

class _NewsCenterPageState extends State<NewsCenterPage> {
  late final NewsInterestRepository _repository;
  late final bool _ownsRepository;
  late Future<NewsInterestProfile> _profileFuture;
  NewsInterestProfile? _profile;
  bool _saving = false;
  String? _status;
  late final NewsRssService _newsService;
  final TextEditingController _customTopicController = TextEditingController();
  final FavoritesRepository _favoritesRepository = FavoritesRepository();
  final InterestFeedbackRepository _feedbackRepository =
      InterestFeedbackRepository();
  Set<String> _lessInterested = <String>{};
  final FavoriteInterestAnalytics _favoriteAnalytics =
      const FavoriteInterestAnalytics();
  NewsSourceLocalizationService get _sourceLocalizationService =>
      NewsSourceLocalizationService(aiEngine: widget.aiEngine);
  late final SharedPreferencesNewsCache _newsCache;
  final NewsFeedbackRepository _newsFeedback = NewsFeedbackRepository();
  Map<String, double> _reactionWeights = const <String, double>{};
  bool _loadingNewsCache = true;
  int _interestRevision = 0;
  List<NewsArticle> _articles = const [];
  bool _showingCachedNews = false;
  bool _refreshingNews = false;
  bool _hasCompletedNewsFetch = false;
  bool _refreshPendingAfterCurrent = false;
  int? _lastRssCandidateCount;
  int? _lastLocalizedCandidateCount;
  int? _lastRankedCandidateCount;
  String? _newsError;
  bool _generatingDigest = false;
  String? _digest;
  String? _digestError;
  final NewsReminderService _reminderService = NewsReminderService();
  bool _morningReminder = false;
  bool _eveningReminder = false;
  bool _loadingReminderSettings = true;
  bool _updatingReminder = false;
  final GlobalKey _interestsSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ownsRepository = widget.repository == null;
    _repository =
        widget.repository ?? SharedPreferencesNewsInterestRepository();
    _newsService = widget.newsService ?? NewsRssService();
    _newsCache = widget.newsCache ?? SharedPreferencesNewsCache();
    _profileFuture = _loadProfile();
    unawaited(_loadReactionWeights());
    unawaited(_loadReminderSettings());
    unawaited(_loadNewsCache());
  }

  @override
  void dispose() {
    if (_ownsRepository) unawaited(_repository.dispose());
    _newsService.dispose();
    _customTopicController.dispose();
    super.dispose();
  }

  Future<NewsInterestProfile> _loadProfile() async {
    final profile = await _repository.load();
    final legacy = widget.legacyPreferences;
    if (legacy == null || legacy.newsInterestsMigrated) return profile;

    // Preserve the user's previously selected categories when the dedicated
    // news-interest profile is first introduced. Do not restore retired
    // categories such as "life" or Telegram channels as news topics.
    final migratedTopics = profile.topics.isNotEmpty
        ? profile.topics
        : _legacyNewsTopics(legacy.categories);
    var result = profile;
    if (profile.topics.isEmpty && migratedTopics.isNotEmpty) {
      result = profile.copyWith(topics: migratedTopics);
      try {
        await _repository.save(result);
      } catch (_) {
        // Keep the migration retryable if the new profile cannot be saved.
        return profile;
      }
    }

    legacy.newsInterestsMigrated = true;
    final preferencesStore = widget.preferencesStore;
    if (preferencesStore != null) {
      try {
        await preferencesStore.save(legacy);
      } catch (_) {
        // The migrated news profile is already saved; a later launch can
        // safely mark the migration complete without re-importing topics.
      }
    }
    return result;
  }

  List<String> _legacyNewsTopics(List<String> categories) {
    const aliases = <String, String>{
      'anime': 'anime',
      'аниме': 'anime',
      'manga': 'manga',
      'манга': 'manga',
      'games': 'games',
      'gaming': 'games',
      'video games': 'games',
      'игры': 'games',
      'гейминг': 'games',
      'видеоигры': 'games',
      'movies': 'movies',
      'movie': 'movies',
      'films': 'movies',
      'film': 'movies',
      'кино': 'movies',
      'фильмы': 'movies',
      'series': 'series',
      'tv series': 'series',
      'сериалы': 'series',
      'technology': 'technology',
      'tech': 'technology',
      'технологии': 'technology',
      'технология': 'technology',
      'artificial intelligence': 'artificial intelligence',
      'ai': 'artificial intelligence',
      'ии': 'artificial intelligence',
      'нейросети': 'artificial intelligence',
      'искусственный интеллект': 'artificial intelligence',
      'science': 'science',
      'наука': 'science',
      'space': 'space',
      'космос': 'space',
      'gadgets': 'gadgets',
      'гаджеты': 'gadgets',
    };
    final topics = <String>{};
    for (final category in categories) {
      final normalized = category.trim().toLowerCase();
      final topic = aliases[normalized];
      if (topic != null) topics.add(topic);
    }
    return topics.toList()..sort();
  }

  Future<void> _loadNewsCache() async {
    final revisionAtStart = _interestRevision;
    NewsInterestProfile? loadedProfile;
    try {
      final profile = await _profileFuture;
      loadedProfile = profile;
      if (!mounted) return;
      setState(() => _profile ??= profile);
      final cached = await Future.wait<Object?>([
        _newsCache.loadArticles(),
        _newsCache.loadDigest(),
        _newsCache.loadTopics(),
        _newsCache.loadIncludeCriticalOutsideInterests(),
      ]);
      final savedTopics = cached[2] as List<String>?;
      final savedCriticalSetting = cached[3] as bool?;
      final favorites = await _favoritesRepository.getAll();
      _lessInterested = await _feedbackRepository.loadLessInterested();
      final favoriteProfile = _favoriteAnalytics.analyze(favorites);
      final cachedArticles = _rankByReaction(
        _favoriteAnalytics.rankNews(
          (cached[0] as List<NewsArticle>),
          favoriteProfile,
          lessInterested: _lessInterested,
        ),
      );
      final selectedTopics = _normalizeTopics(profile.topics);
      final hasFeedInterests =
          profile.topics.isNotEmpty || profile.includeCriticalOutsideInterests;
      final cacheMatchesProfile =
          hasFeedInterests &&
          savedTopics != null &&
          savedCriticalSetting == profile.includeCriticalOutsideInterests &&
          _sameTopics(savedTopics, selectedTopics);
      if (!cacheMatchesProfile) {
        await _newsCache.clear();
      }
      if (!mounted) return;
      setState(() {
        if (revisionAtStart == _interestRevision && cacheMatchesProfile) {
          _articles = cachedArticles;
          _digest = cached[1] as String?;
          _showingCachedNews = cachedArticles.isNotEmpty;
        }
        _loadingNewsCache = false;
      });
      // Do not fetch a generic feed when the user has not selected interests.
      if (hasFeedInterests && _articles.isEmpty) {
        unawaited(_refreshNews());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingNewsCache = false);
      // Cache restoration is best-effort. If storage is unavailable or the
      // cached payload cannot be read, still attempt a fresh feed rather than
      // leaving users with a blank screen until they manually tap Refresh.
      final activeProfile = loadedProfile ?? _profile;
      final hasFeedInterests =
          activeProfile != null &&
          (activeProfile.topics.isNotEmpty ||
              activeProfile.includeCriticalOutsideInterests);
      if (hasFeedInterests && _articles.isEmpty) {
        unawaited(_refreshNews());
      }
    }
  }

  List<String> _normalizeTopics(List<String> topics) {
    final normalized = topics
        .map((topic) => topic.trim().toLowerCase())
        .where((topic) => topic.isNotEmpty)
        .toSet()
        .toList();
    normalized.sort();
    return normalized;
  }

  bool _sameTopics(List<String> first, List<String> second) {
    final normalizedFirst = _normalizeTopics(first);
    final normalizedSecond = _normalizeTopics(second);
    if (normalizedFirst.length != normalizedSecond.length) return false;
    for (var i = 0; i < normalizedFirst.length; i++) {
      if (normalizedFirst[i] != normalizedSecond[i]) return false;
    }
    return true;
  }

  String _emptyFeedMessage(NewsInterestProfile profile) {
    final hasNoTopics = profile.topics.isEmpty;
    final criticalNewsDisabled = !profile.includeCriticalOutsideInterests;
    if (hasNoTopics && criticalNewsDisabled) {
      return 'Выберите интересы ниже, чтобы наполнить ленту подходящими новостями. Общий поток без персонализации не показывается.';
    }
    if (_hasCompletedNewsFetch) {
      return 'По выбранным темам сейчас не найдено подходящих публикаций. Попробуйте добавить более широкую тему или обновить ленту позже.';
    }
    return 'Нажмите «Обновить», чтобы загрузить свежие материалы по выбранным темам.';
  }

  Future<void> _runDiagnostics() async {
    final report = DiagnosticReport(
      createdAt: DateTime.now(),
      checks: [
        DiagnosticCheck(
          name: 'Профиль интересов',
          status: _profile == null
              ? DiagnosticStatus.warning
              : (_profile!.topics.isEmpty
                    ? DiagnosticStatus.warning
                    : DiagnosticStatus.ok),
          details: _profile == null
              ? 'Профиль ещё не загружен'
              : 'Выбрано тем: ${_profile!.topics.length}',
        ),
        DiagnosticCheck(
          name: 'Новостная лента',
          status: _newsError != null
              ? DiagnosticStatus.error
              : (_refreshingNews
                    ? DiagnosticStatus.warning
                    : (_articles.isEmpty
                          ? DiagnosticStatus.warning
                          : DiagnosticStatus.ok)),
          details:
              _newsError ??
              'RSS-кандидатов: ${_lastRssCandidateCount ?? 'нет данных'}; '
                  'после локализации: ${_lastLocalizedCandidateCount ?? 'нет данных'}; '
                  'после персонализации: ${_lastRankedCandidateCount ?? 'нет данных'}; '
                  'на экране: ${_articles.length}'
                  '${_refreshingNews ? '; загрузка ещё выполняется' : ''}',
        ),
        DiagnosticCheck(
          name: 'Локальный кэш',
          status: _loadingNewsCache
              ? DiagnosticStatus.warning
              : DiagnosticStatus.ok,
          details: _loadingNewsCache
              ? 'Восстановление кэша ещё выполняется'
              : 'Загрузка кэша завершена',
        ),
        DiagnosticCheck(
          name: 'Реакции и интересы',
          status: DiagnosticStatus.ok,
          details:
              'Сигналов интереса: ${_reactionWeights.length}; значения хранятся локально',
        ),
        const DiagnosticCheck(
          name: 'Сетевая доступность',
          status: DiagnosticStatus.notChecked,
          details:
              'Проверяется только по результату загрузки ленты; отдельный сетевой тест не запускался',
        ),
      ],
    );
    final reportText = report.toPlainText();
    String? aiAnalysis;
    final engine = widget.aiEngine;
    if (engine != null) {
      try {
        final response = await engine.execute(
          AIRequest(
            id: 'diagnostic-${DateTime.now().microsecondsSinceEpoch}',
            systemInstruction: diagnosticAnalysisInstruction,
            prompt:
                'Проанализируй отчёт OMNI AI. Укажи факты, гипотезы и следующие проверки.\n\n$reportText',
            metadata: const {'feature': 'diagnostics'},
          ),
        );
        aiAnalysis = response.text;
      } catch (_) {
        aiAnalysis =
            'ИИ-анализ недоступен. Сам диагностический отчёт сформирован локально.';
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SystemCorePalette.panel,
        title: const Text('Диагностика OMNI AI'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              '$reportText${aiAnalysis == null ? '' : '\n\nАНАЛИЗ ИИ\n$aiAnalysis'}',
              style: const TextStyle(color: Colors.white70, height: 1.45),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ЗАКРЫТЬ'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadReactionWeights() async {
    try {
      final weights = await _newsFeedback.interestWeights();
      if (!mounted) return;
      setState(() {
        _reactionWeights = weights;
        _articles = _rankByReaction(_articles);
      });
    } catch (_) {
      // Personalization is optional; the feed must still work without storage.
    }
  }

  List<NewsArticle> _rankByReaction(List<NewsArticle> articles) {
    if (_reactionWeights.isEmpty || articles.length < 2) return articles;
    final indexed = articles.indexed.toList();
    double score(NewsArticle article) => article.topics.fold<double>(
      0,
      (total, topic) =>
          total + (_reactionWeights[topic.trim().toLowerCase()] ?? 0),
    );
    indexed.sort((a, b) {
      final byScore = score(b.$2).compareTo(score(a.$2));
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
    });
    return List<NewsArticle>.unmodifiable(indexed.map((entry) => entry.$2));
  }

  Future<void> _reactToArticle(
    NewsArticle article,
    NewsReaction reaction,
  ) async {
    try {
      await _newsFeedback.record(
        articleId: article.id,
        reaction: reaction,
        topics: article.topics,
      );
      final weights = await _newsFeedback.interestWeights();
      if (!mounted) return;
      setState(() {
        _reactionWeights = weights;
        _articles = _rankByReaction(_articles);
        _status = switch (reaction) {
          NewsReaction.like =>
            'Лайк сохранён: интересы будут учтены в рекомендациях.',
          NewsReaction.dislike =>
            'Учтено: похожие материалы будут показываться реже.',
          NewsReaction.opened => 'Просмотр учтён как слабый сигнал интереса.',
        };
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _status =
              'Не удалось сохранить реакцию. Лента продолжит работать.',
        );
      }
    }
  }

  Future<void> _loadReminderSettings() async {
    try {
      final settings = await _reminderService.loadSettings();
      if (!mounted) return;
      setState(() {
        _morningReminder = settings.morning;
        _eveningReminder = settings.evening;
        _loadingReminderSettings = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingReminderSettings = false);
    }
  }

  Future<void> _setReminder({
    required bool morning,
    required bool enabled,
  }) async {
    if (_updatingReminder) return;
    setState(() => _updatingReminder = true);
    try {
      final saved = morning
          ? await _reminderService.setMorningEnabled(enabled)
          : await _reminderService.setEveningEnabled(enabled);
      if (!mounted) return;
      setState(() {
        if (saved) {
          if (morning) {
            _morningReminder = enabled;
          } else {
            _eveningReminder = enabled;
          }
          _status = enabled
              ? 'Напоминание включено. Время указано по часовому поясу устройства.'
              : 'Напоминание отключено.';
        } else {
          _status =
              'Разрешение на уведомления не выдано. Разреши уведомления в настройках Android.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _status =
              'Не удалось настроить уведомление. Проверь разрешения Android.',
        );
      }
    } finally {
      if (mounted) setState(() => _updatingReminder = false);
    }
  }

  Future<void> _save() async {
    final profile = _profile;
    if (profile == null || _saving) return;
    var saved = false;
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      await _repository.save(profile);
      if (!mounted) return;
      saved = true;
      setState(() => _status = 'Настройки интересов сохранены');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Не удалось сохранить настройки');
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    // Applying interests should also populate the feed. Previously saving
    // cleared the old cache but left the news list empty until Refresh was
    // tapped manually.
    final activeProfile = _profile;
    if (saved && mounted && !_loadingNewsCache && activeProfile != null) {
      if (_refreshingNews) {
        // A request for the previous topic selection may still be unwinding.
        // Queue one refresh so saving the new profile cannot leave the feed blank.
        _refreshPendingAfterCurrent = true;
      } else {
        unawaited(_refreshNews());
      }
    }
  }

  Future<void> _refreshNews() async {
    final profile = _profile;
    if (profile == null || _refreshingNews || _loadingNewsCache) return;
    if (profile.topics.isEmpty && !profile.includeCriticalOutsideInterests) {
      setState(() {
        _articles = const [];
        _digest = null;
        _digestError = null;
        _newsError = null;
        _hasCompletedNewsFetch = false;
        _showingCachedNews = false;
      });
      await _newsCache.clear();
      return;
    }
    final revisionAtStart = _interestRevision;
    setState(() {
      _refreshingNews = true;
      _newsError = null;
    });
    try {
      // Search Russian and English editions, while keeping Russian as the
      // app's output language. Feed locale is not the article's geography.
      final fetchedArticles = await _newsService.fetchInternational(profile);
      if (revisionAtStart != _interestRevision) return;
      if (mounted) {
        setState(() => _lastRssCandidateCount = fetchedArticles.length);
      }
      // Prefer an existing Russian edition when a conservative match is found.
      // Foreign articles without a match remain in the feed unchanged.
      final articles = await _sourceLocalizationService.localizeCandidates(
        fetchedArticles,
      );
      if (revisionAtStart != _interestRevision) return;
      if (mounted) {
        setState(() => _lastLocalizedCandidateCount = articles.length);
      }
      final favorites = await _favoritesRepository.getAll();
      _lessInterested = await _feedbackRepository.loadLessInterested();
      final favoriteProfile = _favoriteAnalytics.analyze(favorites);
      final rankedArticles = _rankByReaction(
        _favoriteAnalytics.rankNews(
          articles,
          favoriteProfile,
          lessInterested: _lessInterested,
        ),
      );
      if (revisionAtStart != _interestRevision) return;
      if (mounted) {
        setState(() => _lastRankedCandidateCount = rankedArticles.length);
      }
      // The network feed is usable independently of local cache persistence.
      // Publish the fresh articles first so a storage failure cannot turn a
      // successful RSS refresh into an empty screen.
      if (!mounted) return;
      setState(() {
        _articles = rankedArticles;
        _hasCompletedNewsFetch = true;
        _showingCachedNews = false;
        _digest = null;
        _digestError = null;
        _newsError = null;
      });

      // A digest describes a specific set of articles. Never keep showing a
      // digest generated from the previous feed after a successful refresh.
      // Cache writes are best-effort: report a storage warning, but keep the
      // freshly fetched articles visible if persistence fails.
      try {
        await _newsCache.saveDigest(null);
        if (revisionAtStart != _interestRevision) {
          await _newsCache.clear();
          return;
        }
        await _newsCache.saveArticles(
          rankedArticles,
          selectedTopics: profile.topics,
          includeCriticalOutsideInterests:
              profile.includeCriticalOutsideInterests,
        );
        if (revisionAtStart != _interestRevision) {
          // Topic changes clear the cache too, but an in-flight write may finish
          // afterward. Clear again so stale results cannot survive that race.
          await _newsCache.clear();
          return;
        }
      } catch (_) {
        if (mounted && revisionAtStart == _interestRevision) {
          setState(() {
            _newsError =
                'Новости загружены, но не удалось сохранить их для офлайн-доступа.';
          });
        }
      }
    } catch (error) {
      // A failed request for an old topic selection must not surface an error
      // in the newly selected feed.
      if (!mounted || revisionAtStart != _interestRevision) return;
      final details = error is http.ClientException ? error.message : null;
      setState(() {
        _newsError = details == null || details.isEmpty
            ? 'Не удалось загрузить новости. Проверьте соединение и попробуйте снова.'
            : 'Не удалось загрузить новости: $details';
      });
    } finally {
      if (mounted) {
        setState(() => _refreshingNews = false);
        if (_refreshPendingAfterCurrent) {
          _refreshPendingAfterCurrent = false;
          unawaited(_refreshNews());
        }
      }
    }
  }

  Future<void> _createDigest() async {
    final profile = _profile;
    final engine = widget.aiEngine;
    if (profile == null ||
        engine == null ||
        _generatingDigest ||
        _loadingNewsCache ||
        _refreshingNews) {
      return;
    }
    final revisionAtStart = _interestRevision;
    if ((profile.topics.isEmpty && !profile.includeCriticalOutsideInterests) ||
        _articles.isEmpty) {
      setState(
        () => _digestError = 'Сначала выберите интересы и загрузите новости.',
      );
      return;
    }
    setState(() {
      _generatingDigest = true;
      _digestError = null;
      _digest = null;
    });
    try {
      final digest = await NewsDigestService(
        engine: engine,
      ).createDigest(profile: profile, articles: _articles);
      if (revisionAtStart != _interestRevision) return;
      await _newsCache.saveDigest(digest);
      if (revisionAtStart != _interestRevision) {
        // The selected topics may already have a fresh feed in the cache.
        // A stale digest must not clear those newer articles.
        await _newsCache.saveDigest(null);
        return;
      }
      if (!mounted) return;
      setState(() {
        _digest = digest;
        if (digest == null) {
          _digestError = 'Нет подходящих материалов для дайджеста.';
        }
      });
    } catch (_) {
      // Ignore errors from digest requests started before interests changed.
      if (!mounted || revisionAtStart != _interestRevision) return;
      setState(
        () => _digestError =
            'Не удалось создать дайджест. Проверьте выбранный режим ИИ и попробуйте снова.',
      );
    } finally {
      if (mounted) setState(() => _generatingDigest = false);
    }
  }

  Future<void> _seeLessOf(NewsArticle article) async {
    final topics = article.topics
        .map((topic) => topic.trim().toLowerCase())
        .where((topic) => topic.length >= 2)
        .toSet();
    if (topics.isEmpty) {
      topics.addAll(_favoriteAnalytics.feedbackTermsFor(article).take(3));
    }
    if (topics.isEmpty) return;
    final updated = await _feedbackRepository.addLessInterested(topics);
    final favorites = await _favoritesRepository.getAll();
    final profile = _favoriteAnalytics.analyze(favorites);
    if (!mounted) return;
    setState(() {
      _lessInterested = updated;
      _articles = _favoriteAnalytics.rankNews(
        _articles,
        profile,
        lessInterested: _lessInterested,
      );
      _status = 'Учтено: будем реже поднимать похожие материалы.';
    });
  }

  Future<void> _saveTrailer(NewsArticle article) async {
    await _favoritesRepository.add(
      FavoriteItem(
        id: article.id,
        title: article.title,
        category: FavoriteCategory.trailer,
        addedAt: DateTime.now(),
        description: article.summary,
        interests: article.topics,
        imageUrl: article.thumbnailUrl,
        sourceUrl: (article.videoUrl?.isNotEmpty ?? false)
            ? article.videoUrl
            : article.sourceUrl,
        releaseDate: article.releaseDate,
        releaseDateSourceUrl: article.releaseDateSourceUrl,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Трейлер «${article.title}» сохранён в избранном'),
      ),
    );
  }

  Future<void> _openArticle(NewsArticle article) async {
    unawaited(_reactToArticle(article, NewsReaction.opened));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SystemCorePalette.panel,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  article.sourceName.toUpperCase(),
                  style: const TextStyle(
                    color: SystemCorePalette.green,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  article.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  article.summary.isEmpty
                      ? 'Источник не предоставил краткое описание. Откройте оригинальную публикацию.'
                      : article.summary,
                  style: const TextStyle(color: Colors.white70, height: 1.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Опубликовано: ${article.publishedAt.toLocal()}',
                  style: const TextStyle(
                    color: SystemCorePalette.muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(article.sourceUrl);
                    if (uri != null && uri.scheme == 'https') {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('ОТКРЫТЬ ИСТОЧНИК'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'В приложении показан RSS-фрагмент и краткое описание. Полный материал принадлежит издателю.',
                  style: TextStyle(
                    color: SystemCorePalette.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addCustomTopic() {
    final topic = _customTopicController.text.trim();
    final profile = _profile;
    if (profile == null || topic.isEmpty) return;
    final normalized = topic.toLowerCase();
    if (profile.topics.any(
      (existing) => existing.trim().toLowerCase() == normalized,
    )) {
      setState(() => _status = 'Эта тема уже добавлена.');
      return;
    }
    if (normalized.length > 60) {
      setState(() => _status = 'Сократи тему до 60 символов.');
      return;
    }
    _customTopicController.clear();
    _toggleTopic(normalized, true);
    setState(
      () => _status = 'Тема добавлена. Сохрани интересы, чтобы применить её.',
    );
  }

  void _toggleTopic(String topic, bool selected) {
    final profile = _profile;
    if (profile == null) return;
    final topics = profile.topics.toSet();
    if (selected) {
      topics.add(topic);
    } else {
      topics.remove(topic);
    }
    _interestRevision++;
    setState(() {
      _profile = profile.copyWith(topics: topics.toList());
      _articles = const [];
      _showingCachedNews = false;
      _hasCompletedNewsFetch = false;
      _digest = null;
      _digestError = null;
    });
    unawaited(_newsCache.clear());
  }

  Future<void> _scrollToInterests() async {
    final target = _interestsSectionKey.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.08,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SystemCorePalette.background,
      body: FutureBuilder<NewsInterestProfile>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: SystemCorePalette.green),
            );
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Не удалось загрузить интересы. Перезапустите экран.',
              ),
            );
          }
          final profile = _profile ??= snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  const Text(
                    'OMNI_AI',
                    style: TextStyle(
                      color: Color(0xFFE8F5F5),
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.circle,
                    size: 7,
                    color: SystemCorePalette.green,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'SYSTEM ONLINE',
                    style: TextStyle(
                      color: SystemCorePalette.green,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: SystemCorePalette.panelElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: SystemCorePalette.border),
                  boxShadow: [
                    BoxShadow(
                      color: SystemCorePalette.green.withValues(alpha: 0.05),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PERSONAL INTELLIGENCE',
                      style: TextStyle(
                        color: SystemCorePalette.mint,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                      ),
                    ),
                    SizedBox(height: 9),
                    Text(
                      'ТВОЯ ЛЕНТА',
                      style: TextStyle(
                        color: Color(0xFFE8F5F5),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    SizedBox(height: 7),
                    Text(
                      'Новости по твоим интересам',
                      style: TextStyle(
                        color: SystemCorePalette.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'СЕГОДНЯ  /  ПОДОБРАНО ДЛЯ ТЕБЯ',
                style: TextStyle(
                  color: SystemCorePalette.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 9),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: SystemCorePalette.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: SystemCorePalette.border),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final topic in profile.topics.take(4))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: SystemCorePalette.green.withValues(
                            alpha: 0.08,
                          ),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: SystemCorePalette.green.withValues(
                              alpha: 0.28,
                            ),
                          ),
                        ),
                        child: Text(
                          topic.toUpperCase(),
                          style: const TextStyle(
                            color: SystemCorePalette.green,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    if (profile.topics.length > 4)
                      Text(
                        '+${profile.topics.length - 4} ЕЩЁ',
                        style: const TextStyle(
                          color: SystemCorePalette.muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    TextButton(
                      onPressed: _scrollToInterests,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        profile.topics.isEmpty
                            ? '+ ДОБАВИТЬ ИНТЕРЕСЫ'
                            : '+ ИНТЕРЕСЫ',
                        style: const TextStyle(
                          color: SystemCorePalette.mint,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: (_refreshingNews || _loadingNewsCache)
                    ? null
                    : _refreshNews,
                icon: _refreshingNews
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(
                  _refreshingNews ? 'ЗАГРУЗКА…' : 'ОБНОВИТЬ ПЕРСОНАЛЬНУЮ ЛЕНТУ',
                ),
              ),
              if (_newsError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _newsError!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ],
              if (widget.aiEngine != null) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed:
                      (_generatingDigest ||
                          _loadingNewsCache ||
                          _refreshingNews)
                      ? null
                      : _createDigest,
                  icon: _generatingDigest
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    _generatingDigest
                        ? 'СОЗДАЮ ДАЙДЖЕСТ…'
                        : 'СОЗДАТЬ AI-ДАЙДЖЕСТ',
                  ),
                ),
                if (_digestError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _digestError!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ],
                if (_digest != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: SystemCorePalette.panel,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        _digest!,
                        style: const TextStyle(
                          color: Colors.white,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
              if (_loadingNewsCache) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                ),
              ],
              if (_showingCachedNews &&
                  !_loadingNewsCache &&
                  _articles.isNotEmpty &&
                  !_refreshingNews) ...[
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Показана последняя сохранённая лента; обнови её, чтобы проверить новые публикации.',
                    style: TextStyle(
                      color: SystemCorePalette.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              if (!_refreshingNews &&
                  _newsError == null &&
                  _articles.isEmpty) ...[
                const SizedBox(height: 12),
                const Icon(
                  Icons.rss_feed,
                  size: 34,
                  color: SystemCorePalette.muted,
                ),
                const SizedBox(height: 8),
                Text(
                  _emptyFeedMessage(profile),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: SystemCorePalette.muted,
                    height: 1.4,
                  ),
                ),
              ],
              if (profile.topics.isEmpty &&
                  !profile.includeCriticalOutsideInterests) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _scrollToInterests,
                  icon: const Icon(Icons.tune),
                  label: const Text('НАСТРОИТЬ ИНТЕРЕСЫ'),
                ),
              ],
              for (final article in _articles) ...[
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: SystemCorePalette.panel,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: SystemCorePalette.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(width: 3, color: SystemCorePalette.green),
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _openArticle(article),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    13,
                                    12,
                                    12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${article.sourceName.toUpperCase()}  •  ${article.publishedAt.toLocal().day.toString().padLeft(2, '0')}.${article.publishedAt.toLocal().month.toString().padLeft(2, '0')}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: SystemCorePalette.green,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                          if (article.contentType ==
                                              NewsContentType.trailer)
                                            const Icon(
                                              Icons.play_circle_outline,
                                              size: 17,
                                              color: SystemCorePalette.mint,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        article.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFFE8F5F5),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          height: 1.25,
                                        ),
                                      ),
                                      if (article.summary.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          article.summary,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: SystemCorePalette.muted,
                                            fontSize: 10,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 5,
                                        runSpacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(right: 3),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'ЧИТАТЬ',
                                                  style: TextStyle(
                                                    color:
                                                        SystemCorePalette.mint,
                                                    fontSize: 8,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 0.8,
                                                  ),
                                                ),
                                                SizedBox(width: 4),
                                                Icon(
                                                  Icons.north_east,
                                                  size: 11,
                                                  color: SystemCorePalette.mint,
                                                ),
                                              ],
                                            ),
                                          ),
                                          _ReactionButton(
                                            tooltip:
                                                'Нравится — учитывать в интересах',
                                            icon: Icons.thumb_up_alt_outlined,
                                            color: SystemCorePalette.green,
                                            onPressed: () => _reactToArticle(
                                              article,
                                              NewsReaction.like,
                                            ),
                                          ),
                                          _ReactionButton(
                                            tooltip:
                                                'Не нравится — учитывать в интересах',
                                            icon: Icons.thumb_down_alt_outlined,
                                            color: SystemCorePalette.mint,
                                            onPressed: () => _reactToArticle(
                                              article,
                                              NewsReaction.dislike,
                                            ),
                                          ),
                                          _ReactionButton(
                                            tooltip:
                                                'Показывать меньше похожего',
                                            icon: Icons.remove_circle_outline,
                                            color: SystemCorePalette.muted,
                                            onPressed: () =>
                                                _seeLessOf(article),
                                          ),
                                          if (article.contentType ==
                                              NewsContentType.trailer)
                                            _ReactionButton(
                                              tooltip:
                                                  'Сохранить трейлер в избранное',
                                              icon: Icons.favorite_border,
                                              color: SystemCorePalette.mint,
                                              onPressed: () =>
                                                  _saveTrailer(article),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: SystemCorePalette.panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: profile.topics.isEmpty
                          ? SystemCorePalette.green
                          : SystemCorePalette.border,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: const Icon(
                        Icons.tune,
                        color: SystemCorePalette.green,
                      ),
                      title: const Text(
                        'Настроить интересы новостей',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        profile.topics.isEmpty
                            ? 'Выберите темы, чтобы включить ленту'
                            : 'Выбрано тем: ${profile.topics.length}',
                        style: const TextStyle(
                          color: SystemCorePalette.muted,
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.arrow_downward,
                        color: SystemCorePalette.green,
                      ),
                      onTap: () {
                        final target = _interestsSectionKey.currentContext;
                        if (target != null) {
                          Scrollable.ensureVisible(
                            target,
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeInOut,
                            alignment: 0.05,
                          );
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: SystemCorePalette.panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: SystemCorePalette.border),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: const Icon(
                        Icons.health_and_safety_outlined,
                        color: SystemCorePalette.green,
                      ),
                      title: const Text(
                        'Диагностика системы',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: const Text(
                        'Проверить ленту и сформировать отчёт для поиска ошибок',
                        style: TextStyle(
                          color: SystemCorePalette.muted,
                          fontSize: 12,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: SystemCorePalette.green,
                      ),
                      onTap: _runDiagnostics,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              Text(
                'ВАШИ ИНТЕРЕСЫ',
                key: _interestsSectionKey,
                style: TextStyle(
                  color: SystemCorePalette.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Лента показывает новости только по выбранным интересам. Добавьте темы ниже, чтобы начать.',
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customTopicController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addCustomTopic(),
                      maxLength: 60,
                      decoration: const InputDecoration(
                        labelText: 'Своя тема',
                        hintText:
                            'Например: робототехника, экология, Формула-1',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Добавить тему',
                    onPressed: _addCustomTopic,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Можно добавить собственные темы — лента будет искать материалы по ним.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 18),
              if (profile.topics.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final topic in profile.topics)
                      InputChip(
                        label: Text(topic),
                        selected: true,
                        selectedColor: SystemCorePalette.green.withValues(
                          alpha: 0.18,
                        ),
                        onDeleted: () => _toggleTopic(topic, false),
                        deleteIconColor: SystemCorePalette.green,
                      ),
                  ],
                )
              else
                const Text(
                  'Пока нет тем. Добавьте любую тему выше — например, название игры, автора, команду или научное направление.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              const SizedBox(height: 18),
              const Divider(color: Colors.white12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Критические новости вне интересов'),
                subtitle: const Text(
                  'Отдельное исключение. По умолчанию выключено.',
                  style: TextStyle(color: SystemCorePalette.muted),
                ),
                value: profile.includeCriticalOutsideInterests,
                activeThumbColor: SystemCorePalette.green,
                onChanged: (value) {
                  _interestRevision++;
                  setState(() {
                    _profile = profile.copyWith(
                      includeCriticalOutsideInterests: value,
                    );
                    _articles = const [];
                    _showingCachedNews = false;
                    _hasCompletedNewsFetch = false;
                    _digest = null;
                    _digestError = null;
                    _newsError = null;
                  });
                  unawaited(_newsCache.clear());
                },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'СОХРАНЕНИЕ…' : 'СОХРАНИТЬ ИНТЕРЕСЫ'),
              ),
              if (_status != null) ...[
                const SizedBox(height: 10),
                Text(
                  _status!,
                  style: const TextStyle(color: SystemCorePalette.green),
                ),
              ],
              const SizedBox(height: 28),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
              const Text(
                'РАСПИСАНИЕ ДАЙДЖЕСТА',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Напоминания по местному времени. По нажатию открой приложение, обнови ленту и создай дайджест. Само уведомление не запускает фоновую загрузку или генерацию ИИ.',
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              if (_loadingReminderSettings)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                )
              else ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Утреннее напоминание — 08:00'),
                  subtitle: const Text('Персональные новости на начало дня'),
                  value: _morningReminder,
                  onChanged: _updatingReminder
                      ? null
                      : (value) => _setReminder(morning: true, enabled: value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Вечернее напоминание — 18:00'),
                  subtitle: const Text('Обновить новости ещё раз за день'),
                  value: _eveningReminder,
                  onChanged: _updatingReminder
                      ? null
                      : (value) => _setReminder(morning: false, enabled: value),
                ),
              ],
              const SizedBox(height: 28),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: SystemCorePalette.panelElevated,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 36,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: SystemCorePalette.border),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}
