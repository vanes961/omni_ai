import 'dart:convert';

import 'package:http/http.dart' as http;

/// A chapter that has an explicitly Russian translation on MangaDex.
class MangaChapterOption {
  const MangaChapterOption({
    required this.id,
    required this.mangaId,
    required this.chapter,
    required this.title,
    required this.pageCount,
    required this.language,
    this.volume,
    this.publishedAt,
  });

  final String id;
  final String mangaId;
  final String chapter;
  final String title;
  final int pageCount;
  final String language;
  final String? volume;
  final DateTime? publishedAt;

  String get displayLabel => chapter.trim().isEmpty ? 'Без номера' : chapter;
}

/// Manifest of image pages returned by MangaDex's at-home endpoint.
class MangaChapterPageSet {
  const MangaChapterPageSet({
    required this.chapterId,
    required this.imageUrls,
    required this.dataSaverImageUrls,
  });

  final String chapterId;
  final List<Uri> imageUrls;
  final List<Uri> dataSaverImageUrls;

  List<Uri> urls({bool dataSaver = false}) =>
      dataSaver ? dataSaverImageUrls : imageUrls;

  static MangaChapterPageSet? parse(Object? payload, {required String chapterId}) {
    if (payload is! Map<String, dynamic>) return null;
    final baseUrlRaw = payload['baseUrl'];
    final chapter = payload['chapter'];
    if (baseUrlRaw is! String || chapter is! Map<String, dynamic>) {
      return null;
    }
    final baseUrl = Uri.tryParse(baseUrlRaw);
    final hash = chapter['hash'];
    final data = chapter['data'];
    final dataSaver = chapter['dataSaver'];
    if (!_isTrustedCdn(baseUrl) ||
        hash is! String ||
        hash.isEmpty ||
        data is! List ||
        dataSaver is! List) {
      return null;
    }
    final fullUrls = _buildUrls(baseUrl!, hash, data);
    final saverUrls = _buildUrls(baseUrl, hash, dataSaver);
    if (fullUrls == null || saverUrls == null || fullUrls.isEmpty) return null;
    return MangaChapterPageSet(
      chapterId: chapterId,
      imageUrls: List<Uri>.unmodifiable(fullUrls),
      dataSaverImageUrls: List<Uri>.unmodifiable(saverUrls),
    );
  }

  static bool _isTrustedCdn(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      (uri.host == 'mangadex.org' ||
          uri.host.endsWith('.mangadex.org') ||
          uri.host.endsWith('.mangadex.network'));

  static List<Uri>? _buildUrls(Uri baseUrl, String hash, List<dynamic> names) {
    final output = <Uri>[];
    for (final rawName in names) {
      if (rawName is! String ||
          rawName.isEmpty ||
          rawName.contains('/') ||
          rawName.contains('\\') ||
          rawName == '.' ||
          rawName == '..') {
        return null;
      }
      output.add(
        baseUrl.resolve('/data/$hash/${Uri.encodeComponent(rawName)}'),
      );
    }
    return output;
  }
}

/// Fetches only Russian-translated chapters. It intentionally does not fall
/// back to English or another language when a Russian chapter is unavailable.
///
/// Results are paginated, requests are bounded by [timeout], and identical
/// in-flight chapter-page requests are coalesced to avoid duplicate traffic.
class MangaChapterService {
  MangaChapterService({
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client();

  static const String apiBase = 'https://api.mangadex.org';
  static const String _userAgent = 'OMNI_AI/1.0 (Russian manga reader)';
  final http.Client _client;
  final Duration timeout;
  final Map<String, Future<MangaChapterPageSet?>> _pageRequests = {};

  Future<List<MangaChapterOption>> fetchRussianChapters(
    String mangaId, {
    int offset = 0,
    int limit = 100,
  }) async {
    final id = mangaId.trim();
    if (id.isEmpty || offset < 0 || limit < 1) return const [];
    final boundedLimit = limit.clamp(1, 100);
    final uri = Uri.parse('$apiBase/chapter').replace(
      queryParameters: {
        'manga': id,
        'limit': '$boundedLimit',
        'offset': '$offset',
        'translatedLanguage[]': ['ru'],
        'order[volume]': 'asc',
        'order[chapter]': 'asc',
        'includeFuturePublishAt': '0',
        'includeEmptyPages': '0',
        'contentRating[]': ['safe'],
      },
    );

    final response = await _client
        .get(uri, headers: const {'accept': 'application/json', 'User-Agent': _userAgent})
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw MangaChapterServiceException(
        'Не удалось загрузить список русских глав (HTTP ${response.statusCode}).',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const MangaChapterServiceException(
        'Сервис глав вернул некорректные данные.',
      );
    }
    return parseRussianChapters(decoded, mangaId: id);
  }

  static List<MangaChapterOption> parseRussianChapters(
    Object? payload, {
    required String mangaId,
  }) {
    if (payload is! Map<String, dynamic> || payload['data'] is! List) {
      return const [];
    }
    final output = <MangaChapterOption>[];
    final seen = <String>{};
    for (final raw in payload['data'] as List) {
      if (raw is! Map<String, dynamic>) continue;
      final id = raw['id'];
      final attributes = raw['attributes'];
      if (id is! String ||
          id.trim().isEmpty ||
          !seen.add(id) ||
          attributes is! Map<String, dynamic> ||
          attributes['translatedLanguage'] != 'ru') {
        continue;
      }
      final pagesRaw = attributes['pages'];
      final pages = pagesRaw is int && pagesRaw >= 0 ? pagesRaw : 0;
      final chapterRaw = attributes['chapter'];
      final volumeRaw = attributes['volume'];
      final titleRaw = attributes['title'];
      final publishRaw = attributes['publishAt'];
      output.add(
        MangaChapterOption(
          id: id,
          mangaId: mangaId,
          chapter: chapterRaw is String ? chapterRaw : '',
          title: titleRaw is String ? titleRaw.trim() : '',
          pageCount: pages,
          language: 'ru',
          volume: volumeRaw is String && volumeRaw.trim().isNotEmpty
              ? volumeRaw.trim()
              : null,
          publishedAt: publishRaw is String
              ? DateTime.tryParse(publishRaw)?.toUtc()
              : null,
        ),
      );
    }
    return List<MangaChapterOption>.unmodifiable(output);
  }

  Future<MangaChapterPageSet?> fetchPages(
    String chapterId, {
    bool dataSaver = false,
  }) async {
    final id = chapterId.trim();
    if (id.isEmpty) return null;
    final manifest = await _pageRequests.putIfAbsent(id, () async {
      try {
        final response = await _client
            .get(
              Uri.parse('$apiBase/at-home/server/$id'),
              headers: const {'accept': 'application/json', 'User-Agent': _userAgent},
            )
            .timeout(timeout);
        if (response.statusCode != 200) {
          throw MangaChapterServiceException(
            'Не удалось загрузить страницы главы (HTTP ${response.statusCode}).',
          );
        }
        final Object? decoded;
        try {
          decoded = jsonDecode(response.body);
        } on FormatException {
          throw const MangaChapterServiceException(
            'Сервис страниц вернул некорректные данные.',
          );
        }
        return MangaChapterPageSet.parse(decoded, chapterId: id);
      } finally {
        _pageRequests.remove(id);
      }
    });
    if (manifest == null) return null;
    // The same manifest carries both sizes; the caller chooses URLs to bound
    // image transfer size without repeating the metadata request.
    return dataSaver
        ? MangaChapterPageSet(
            chapterId: manifest.chapterId,
            imageUrls: manifest.dataSaverImageUrls,
            dataSaverImageUrls: manifest.dataSaverImageUrls,
          )
        : manifest;
  }

  void close() {
    _pageRequests.clear();
    _client.close();
  }
}

class MangaChapterServiceException implements Exception {
  const MangaChapterServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
