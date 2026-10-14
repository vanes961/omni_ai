import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  const MangaReaderPage({
    required this.manga,
    this.chapterService,
    this.progressRepository,
    super.key,
  });

  final MangaCatalogItem manga;
  final MangaChapterService? chapterService;
  final MangaReadingProgressRepository? progressRepository;

  @override
  State<MangaReaderPage> createState() => _MangaReaderPageState();
}

class _MangaReaderPageState extends State<MangaReaderPage> {
  late final MangaChapterService _service =
      widget.chapterService ?? MangaChapterService();
  late final MangaReadingProgressRepository _progress =
      widget.progressRepository ?? MangaReadingProgressRepository();
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
        final savedChapterId = saved.chapterId;
        final foundById = savedChapterId == null
            ? -1
            : all.indexWhere((chapter) => chapter.id == savedChapterId);
        final found = foundById >= 0
            ? foundById
            : all.indexWhere(
                (chapter) => chapter.chapter == saved.chapterLabel,
              );
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
      chapterId: _chapters[_chapterIndex].id,
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
                final pageDecodeWidth =
                    (constraints.maxWidth.clamp(1.0, 900.0) *
                            MediaQuery.devicePixelRatioOf(context))
                        .round();
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
                              // Keep decoded/laid-out off-screen pages bounded to one viewport.
                              scrollCacheExtent:
                                  const ScrollCacheExtent.viewport(1.0),
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
                                    memCacheWidth: pageDecodeWidth,
                                    maxWidthDiskCache: pageDecodeWidth,
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
