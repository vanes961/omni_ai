import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/data/manga_reading_progress_repository.dart';
import 'package:omni_ai/features/media/presentation/manga_catalog_page.dart';
import 'package:omni_ai/features/media/services/manga_catalog_service.dart';
import 'package:omni_ai/features/media/services/manga_chapter_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('restores the saved chapter and exposes retry when pages fail', (
    tester,
  ) async {
    final store = _MemoryProgressStore();
    final progress = MangaReadingProgressRepository(store: store);
    await progress.save(
      MangaReadingProgress(
        mangaId: 'mangadex:test-manga',
        chapterIndex: 1,
        // The stable ID must win even if a legacy display label is stale.
        chapterLabel: '1',
        chapterId: 'ch-2',
        page: 2,
        pageOffset: 0.4,
        updatedAt: DateTime.utc(2026, 10, 14),
      ),
    );
    final chapters = _FakeChapterService();

    await tester.pumpWidget(
      MaterialApp(
        home: MangaReaderPage(
          manga: const MangaCatalogItem(
            id: 'test-manga',
            title: 'Тестовая манга',
            description: '',
            status: 'ongoing',
            sourceUrl: 'https://mangadex.org/title/test-manga',
            coverUrl: '',
            authors: [],
          ),
          chapterService: chapters,
          progressRepository: progress,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Гл. 2'), findsOneWidget);
    expect(find.text('Страницы этой главы недоступны.'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);
    expect(chapters.pageRequests, 1);

    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();

    expect(chapters.pageRequests, 2);
    expect(find.text('Страницы этой главы недоступны.'), findsOneWidget);
  });

  testWidgets('restores a saved chapter beyond the initial 500-chapter window', (
    tester,
  ) async {
    final store = _MemoryProgressStore();
    final progress = MangaReadingProgressRepository(store: store);
    await progress.save(
      MangaReadingProgress(
        mangaId: 'mangadex:test-manga',
        chapterIndex: 500,
        chapterLabel: '501',
        chapterId: 'ch-501',
        page: 1,
        updatedAt: DateTime.utc(2026, 10, 14),
      ),
    );
    final chapters = _FakeChapterService(totalChapters: 600);

    await tester.pumpWidget(
      MaterialApp(
        home: MangaReaderPage(
          manga: const MangaCatalogItem(
            id: 'test-manga',
            title: 'Тестовая манга',
            description: '',
            status: 'ongoing',
            sourceUrl: 'https://mangadex.org/title/test-manga',
            coverUrl: '',
            authors: [],
          ),
          chapterService: chapters,
          progressRepository: progress,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Гл. 501'), findsOneWidget);
    expect(chapters.requestedOffsets, contains(500));
    expect(chapters.requestedChapterIds, contains('ch-501'));
  });

  testWidgets('chapter picker switches the active chapter after page error', (
    tester,
  ) async {
    final chapters = _FakeChapterService();

    await tester.pumpWidget(
      MaterialApp(
        home: MangaReaderPage(
          manga: const MangaCatalogItem(
            id: 'test-manga',
            title: 'Тестовая манга',
            description: '',
            status: 'ongoing',
            sourceUrl: 'https://mangadex.org/title/test-manga',
            coverUrl: '',
            authors: [],
          ),
          chapterService: chapters,
          progressRepository: MangaReadingProgressRepository(
            store: _MemoryProgressStore(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Гл. 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('manga-reader-chapter-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('manga-chapter-ch-2')));
    await tester.pumpAndSettle();

    expect(find.text('Гл. 2'), findsOneWidget);
    expect(find.text('Страницы этой главы недоступны.'), findsOneWidget);
    expect(chapters.requestedChapterIds, contains('ch-2'));
  });
}

class _FakeChapterService extends MangaChapterService {
  _FakeChapterService({this.totalChapters = 2});

  final int totalChapters;
  int pageRequests = 0;
  final List<String> requestedChapterIds = [];
  final List<int> requestedOffsets = [];

  @override
  Future<List<MangaChapterOption>> fetchRussianChapters(
    String mangaId, {
    int offset = 0,
    int limit = 100,
  }) async {
    requestedOffsets.add(offset);
    if (offset >= totalChapters) return const [];
    final end = (offset + limit).clamp(0, totalChapters);
    return [
      for (var index = offset; index < end; index++)
        MangaChapterOption(
          id: 'ch-${index + 1}',
          mangaId: 'test-manga',
          chapter: '${index + 1}',
          title: index == 0
              ? 'Первая глава'
              : index == 1
              ? 'Вторая глава'
              : 'Глава ${index + 1}',
          pageCount: index == 1 ? 10 : 12,
          language: 'ru',
        ),
    ];
  }

  @override
  Future<MangaChapterPageSet?> fetchPages(
    String chapterId, {
    bool dataSaver = false,
  }) async {
    pageRequests++;
    requestedChapterIds.add(chapterId);
    return null;
  }
}

class _MemoryProgressStore implements MangaProgressStringStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
