import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/data/cross_content_recommendation.dart';
import 'package:omni_ai/features/media/data/manga_reading_progress_repository.dart';

void main() {
  group('MangaReadingProgressRepository', () {
    test('persists and restores progress after repository recreation', () async {
      final store = _MemoryMangaProgressStore();
      final repository = MangaReadingProgressRepository(store: store);
      final updatedAt = DateTime.utc(2026, 10, 14, 12, 30);
      await repository.save(
        MangaReadingProgress(
          mangaId: 'mangadex:abc-123',
          chapterIndex: 12,
          chapterLabel: '12.5',
          chapterId: 'chapter-stable-id',
          page: 7,
          pageOffset: 0.35,
          updatedAt: updatedAt,
        ),
      );

      final restored = await MangaReadingProgressRepository(
        store: store,
      ).getById('mangadex:abc-123');

      expect(restored, isNotNull);
      expect(restored!.mangaId, 'mangadex:abc-123');
      expect(restored.chapterIndex, 12);
      expect(restored.chapterLabel, '12.5');
      expect(restored.chapterId, 'chapter-stable-id');
      expect(restored.page, 7);
      expect(restored.pageOffset, 0.35);
      expect(restored.updatedAt, updatedAt);
    });

    test('restores older records without a page offset at the top of the page', () {
      final record = MangaReadingProgress.fromJson({
        'mangaId': 'mangadex:old-record',
        'chapterIndex': 1,
        'chapterLabel': '1',
        'page': 4,
        'updatedAt': '2026-10-14T12:00:00.000Z',
      });

      expect(record, isNotNull);
      expect(record!.page, 4);
      expect(record.pageOffset, 0);
    });

    test('rejects out-of-range normalized page offsets', () async {
      final repository = MangaReadingProgressRepository(
        store: _MemoryMangaProgressStore(),
      );
      expect(
        () => repository.save(
          MangaReadingProgress(
            mangaId: 'mangadex:abc',
            chapterIndex: 1,
            page: 2,
            pageOffset: 1.1,
            updatedAt: DateTime.utc(2026),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('adapts saved manga progress to spoiler-aware recommendations', () async {
      final saved = _progress('mangadex:source', 8, 1);
      final progress = saved.toCrossContentProgress();
      const relation = CrossContentRelation(
        sourceId: 'mangadex:source',
        targetId: 'tmdb:tv:anime',
        sourceType: CrossContentType.manga,
        targetType: CrossContentType.anime,
        kind: CrossContentRelationKind.adaptation,
        sourceName: 'Verified catalog',
        sourceUrl: 'https://catalog.example/relation',
        confidence: 0.95,
        requiredSourceChapter: 8,
        safeTargetEpisode: 1,
      );

      final recommendations = const CrossContentRecommendationEngine().recommend(
        progress: progress,
        relations: [relation],
      );
      final lockedRecommendations =
          const CrossContentRecommendationEngine().recommend(
            progress: CrossContentProgress(
              contentId: 'mangadex:source',
              type: CrossContentType.manga,
              chapter: 7,
            ),
            relations: [relation],
          );

      expect(progress.contentId, 'mangadex:source');
      expect(progress.type, CrossContentType.manga);
      expect(progress.position, 8);
      expect(recommendations.map((item) => item.targetId), ['tmdb:tv:anime']);
      expect(recommendations.single.safeStartPosition, 1);
      expect(lockedRecommendations, isEmpty);
    });

    test('updates one record per manga and sorts by most recent progress', () async {
      final store = _MemoryMangaProgressStore();
      final repository = MangaReadingProgressRepository(store: store);
      await repository.save(_progress('mangadex:first', 2, 1));
      await repository.save(_progress('mangadex:second', 4, 2));
      await repository.save(_progress('mangadex:first', 8, 3));

      final records = await repository.getAll();
      expect(records, hasLength(2));
      expect(records.map((record) => record.mangaId), [
        'mangadex:first',
        'mangadex:second',
      ]);
      expect(records.first.chapterIndex, 8);
    });

    test('deletes a manga progress record without affecting other records', () async {
      final store = _MemoryMangaProgressStore();
      final repository = MangaReadingProgressRepository(store: store);
      await repository.save(_progress('mangadex:first', 2, 1));
      await repository.save(_progress('mangadex:second', 4, 2));

      await repository.delete('mangadex:first');

      expect((await repository.getAll()).map((record) => record.mangaId), [
        'mangadex:second',
      ]);
      expect(await repository.getById('mangadex:first'), isNull);
    });

    test('clears malformed storage and returns an empty list', () async {
      final store = _MemoryMangaProgressStore()
        ..values[MangaReadingProgressRepository.storageKey] = '{invalid';
      final repository = MangaReadingProgressRepository(store: store);

      expect(await repository.getAll(), isEmpty);
      expect(store.values, isEmpty);
    });

    test('skips malformed entries but retains valid progress', () async {
      final store = _MemoryMangaProgressStore()
        ..values[MangaReadingProgressRepository.storageKey] = jsonEncode({
          'version': 1,
          'records': [
            _progress('mangadex:valid', 3, 1).toJson(),
            {'mangaId': 'invalid', 'chapterIndex': -1},
          ],
        });
      final repository = MangaReadingProgressRepository(store: store);

      final records = await repository.getAll();

      expect(records, hasLength(1));
      expect(records.single.mangaId, 'mangadex:valid');
      final saved = jsonDecode(
        store.values[MangaReadingProgressRepository.storageKey]!,
      ) as Map<String, dynamic>;
      expect(saved['records'], hasLength(1));
    });

    test('rejects invalid identifiers, chapter indexes, and page indexes', () async {
      final repository = MangaReadingProgressRepository(
        store: _MemoryMangaProgressStore(),
      );
      expect(
        () => repository.save(_progress('tmdb:movie:1', 1, 1)),
        throwsArgumentError,
      );
      expect(
        () => repository.save(_progress('mangadex:abc', -1, 1)),
        throwsArgumentError,
      );
      expect(
        () => repository.save(
          MangaReadingProgress(
            mangaId: 'mangadex:abc',
            chapterIndex: 1,
            page: 0,
            updatedAt: DateTime.utc(2026),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('rejects unknown storage schema versions', () async {
      final store = _MemoryMangaProgressStore()
        ..values[MangaReadingProgressRepository.storageKey] = jsonEncode({
          'version': 99,
          'records': [],
        });
      final repository = MangaReadingProgressRepository(store: store);

      await expectLater(repository.getAll(), throwsFormatException);
    });
  });
}

MangaReadingProgress _progress(String id, int chapter, int minute) =>
    MangaReadingProgress(
      mangaId: id,
      chapterIndex: chapter,
      updatedAt: DateTime.utc(2026, 10, 14, 12, minute),
    );

class _MemoryMangaProgressStore implements MangaProgressStringStore {
  final Map<String, String> values = <String, String>{};

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
