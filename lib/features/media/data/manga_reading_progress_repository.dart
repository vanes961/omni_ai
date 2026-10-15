import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cross_content_recommendation.dart';

/// Last known manga reading position, independent from the catalogue UI.
class MangaReadingProgress {
  const MangaReadingProgress({
    required this.mangaId,
    required this.chapterIndex,
    required this.updatedAt,
    this.chapterLabel = '',
    this.chapterId,
    this.page,
    this.pageOffset = 0,
  });

  /// Stable catalogue ID, for example `mangadex:<uuid>`.
  final String mangaId;

  /// Monotonic chapter position used for spoiler-safe recommendation boundaries.
  final int chapterIndex;

  /// Optional provider-specific display label (for example "12.5" or "Extra").
  final String chapterLabel;

  /// Stable MangaDex chapter ID; used before the display-label fallback.
  final String? chapterId;

  /// One-based page position within the chapter, when known.
  final int? page;

  /// Normalized vertical offset within [page], from 0.0 to 1.0.
  /// Older records without this field restore to the top of their saved page.
  final double pageOffset;

  final DateTime updatedAt;

  /// Parses a conservative chapter boundary from the provider's chapter label.
  ///
  /// [chapterIndex] is a zero-based position in the currently loaded catalogue,
  /// not the manga's chapter number, so it must never unlock spoiler boundaries.
  int? get spoilerSafeChapterPosition {
    final value = double.tryParse(chapterLabel.trim());
    if (value == null || !value.isFinite || value < 1) return null;

    // Fractional chapters only unlock after the next whole-number boundary.
    return value.ceil();
  }

  /// Adapts persisted manga progress to the shared spoiler-aware engine.
  CrossContentProgress toCrossContentProgress() => CrossContentProgress(
    contentId: mangaId,
    type: CrossContentType.manga,
    chapter: spoilerSafeChapterPosition,
  );

  Map<String, Object?> toJson() => {
    'mangaId': mangaId,
    'chapterIndex': chapterIndex,
    'chapterLabel': chapterLabel,
    'chapterId': chapterId,
    'page': page,
    'pageOffset': pageOffset,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static MangaReadingProgress? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final mangaId = value['mangaId'];
    final chapterIndex = value['chapterIndex'];
    final chapterLabel = value['chapterLabel'];
    final chapterId = value['chapterId'];
    final page = value['page'];
    final pageOffsetRaw = value['pageOffset'];
    final pageOffset = pageOffsetRaw is num ? pageOffsetRaw.toDouble() : 0.0;
    final updatedAt = value['updatedAt'];
    if (mangaId is! String ||
        !mangaId.startsWith('mangadex:') ||
        mangaId.trim().length <= 'mangadex:'.length ||
        chapterIndex is! int ||
        chapterIndex < 0 ||
        (page != null && (page is! int || page < 1)) ||
        (pageOffsetRaw != null && pageOffsetRaw is! num) ||
        !pageOffset.isFinite ||
        pageOffset < 0 ||
        pageOffset > 1 ||
        (chapterLabel != null && chapterLabel is! String) ||
        (chapterId != null &&
            (chapterId is! String || chapterId.trim().isEmpty)) ||
        updatedAt is! String) {
      return null;
    }
    final parsedDate = DateTime.tryParse(updatedAt);
    if (parsedDate == null) return null;
    return MangaReadingProgress(
      mangaId: mangaId,
      chapterIndex: chapterIndex,
      chapterLabel: chapterLabel as String? ?? '',
      chapterId: chapterId as String?,
      page: page as int?,
      pageOffset: pageOffset,
      updatedAt: parsedDate.toUtc(),
    );
  }
}

abstract interface class MangaProgressStringStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// Persistent local progress storage. It stores positions only, not manga
/// pages or account credentials, and is deliberately independent from UI code.
class MangaReadingProgressRepository {
  MangaReadingProgressRepository({MangaProgressStringStore? store})
    : _store = store ?? _SharedPreferencesMangaProgressStore();

  static const String storageKey = 'omni_ai.manga_progress.v1';
  static const int _formatVersion = 1;

  final MangaProgressStringStore _store;
  Future<void> _operations = Future<void>.value();

  Future<List<MangaReadingProgress>> getAll() => _serialize(_readAll);

  Future<MangaReadingProgress?> getById(String mangaId) async {
    final records = await getAll();
    for (final record in records) {
      if (record.mangaId == mangaId) return record;
    }
    return null;
  }

  Future<void> save(MangaReadingProgress progress) {
    if (!progress.mangaId.startsWith('mangadex:') ||
        progress.mangaId.trim().length <= 'mangadex:'.length) {
      throw ArgumentError.value(
        progress.mangaId,
        'mangaId',
        'Expected a stable mangadex:<id> identifier.',
      );
    }
    if (progress.chapterIndex < 0) {
      throw ArgumentError.value(
        progress.chapterIndex,
        'chapterIndex',
        'Must be zero or positive.',
      );
    }
    if (progress.page != null && progress.page! < 1) {
      throw ArgumentError.value(progress.page, 'page', 'Must be one-based.');
    }
    if (!progress.pageOffset.isFinite ||
        progress.pageOffset < 0 ||
        progress.pageOffset > 1) {
      throw ArgumentError.value(
        progress.pageOffset,
        'pageOffset',
        'Must be a finite normalized offset between 0 and 1.',
      );
    }
    return _serialize(() async {
      final records = await _readAll();
      records.removeWhere((record) => record.mangaId == progress.mangaId);
      records.add(
        MangaReadingProgress(
          mangaId: progress.mangaId,
          chapterIndex: progress.chapterIndex,
          chapterLabel: progress.chapterLabel,
          chapterId: progress.chapterId,
          page: progress.page,
          pageOffset: progress.pageOffset,
          updatedAt: progress.updatedAt.toUtc(),
        ),
      );
      records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await _writeAll(records);
    });
  }

  Future<void> delete(String mangaId) {
    return _serialize(() async {
      final records = await _readAll();
      final initialLength = records.length;
      records.removeWhere((record) => record.mangaId == mangaId);
      if (records.length != initialLength) await _writeAll(records);
    });
  }

  Future<List<MangaReadingProgress>> _readAll() async {
    final encoded = await _store.read(storageKey);
    if (encoded == null || encoded.isEmpty) return <MangaReadingProgress>[];

    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      await _store.remove(storageKey);
      return <MangaReadingProgress>[];
    }

    if (decoded is! Map<String, dynamic> || decoded['records'] is! List) {
      await _store.remove(storageKey);
      return <MangaReadingProgress>[];
    }
    if (decoded['version'] != _formatVersion) {
      throw const FormatException('Unsupported manga progress data version.');
    }

    var invalidRecordFound = false;
    final records = <MangaReadingProgress>[];
    for (final raw in decoded['records'] as List) {
      final record = MangaReadingProgress.fromJson(raw);
      if (record == null) {
        invalidRecordFound = true;
      } else {
        records.add(record);
      }
    }
    records.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (invalidRecordFound) await _writeAll(records);
    return records;
  }

  Future<void> _writeAll(List<MangaReadingProgress> records) {
    return _store.write(
      storageKey,
      jsonEncode({
        'version': _formatVersion,
        'records': [for (final record in records) record.toJson()],
      }),
    );
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operations = _operations.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

class _SharedPreferencesMangaProgressStore implements MangaProgressStringStore {
  SharedPreferencesAsync? _instance;

  SharedPreferencesAsync get _preferences =>
      _instance ??= SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<void> remove(String key) => _preferences.remove(key);
}
