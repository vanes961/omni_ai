import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omni_ai/features/media/data/source_discovery_service.dart';
import 'package:omni_ai/features/media/data/video_source_provider.dart';

/// Discovers the Internet Archive's public catalogue as an initial playback
/// provider. This is a real provider, not a list of search-page links.
class InternetArchiveDiscoveryAdapter implements SourceDiscoveryAdapter {
  @override
  String get id => 'internet-archive';

  @override
  Future<Iterable<DiscoveredSourceCandidate>> discover({
    required Set<PlaybackMediaKind> mediaKinds,
  }) async {
    if (!mediaKinds.contains(PlaybackMediaKind.movie)) {
      return const <DiscoveredSourceCandidate>[];
    }
    return const [
      DiscoveredSourceCandidate(
        id: 'internet-archive',
        name: 'Internet Archive (открыто лицензированные фильмы)',
        baseUri: Uri(scheme: 'https', host: 'archive.org'),
        mediaKinds: {PlaybackMediaKind.movie},
        capabilities: {DiscoveredSourceCapability.playback},
        discoveredBy: 'internet-archive',
        note: 'Поиск только по материалам с распознанной открытой лицензией.',
      ),
    ];
  }
}

/// Checks that the known provider endpoint is reachable before registration.
class InternetArchiveSourceProbe implements DiscoveredSourceProbe {
  InternetArchiveSourceProbe({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<DiscoveredSourceCandidate> check(
    DiscoveredSourceCandidate candidate,
  ) async {
    if (candidate.id != 'internet-archive' ||
        candidate.baseUri.host != 'archive.org' ||
        candidate.baseUri.scheme != 'https') {
      return candidate.copyWith(
        status: DiscoveredSourceStatus.rejected,
        checkedAt: DateTime.now(),
        note: 'Неизвестный адрес источника.',
      );
    }

    final response = await _client
        .get(Uri.https('archive.org', '/'))
        .timeout(const Duration(seconds: 8));
    return candidate.copyWith(
      status: response.statusCode >= 200 && response.statusCode < 500
          ? DiscoveredSourceStatus.available
          : DiscoveredSourceStatus.unavailable,
      checkedAt: DateTime.now(),
      note: response.statusCode >= 200 && response.statusCode < 500
          ? 'Каталог доступен; видеопотоки проверяются отдельно.'
          : 'Каталог вернул HTTP ${response.statusCode}.',
    );
  }
}

/// Resolves films explicitly marked public domain or Creative Commons on
/// Internet Archive. Search results without a recognized open license are
/// excluded rather than presented as playable.
class InternetArchivePlaybackProvider implements VideoSourceProvider {
  InternetArchivePlaybackProvider({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const _openLicenses = <String>{
    'http://creativecommons.org/publicdomain/mark/1.0/',
    'https://creativecommons.org/publicdomain/mark/1.0/',
    'http://creativecommons.org/licenses/by/4.0/',
    'https://creativecommons.org/licenses/by/4.0/',
    'http://creativecommons.org/licenses/by-sa/4.0/',
    'https://creativecommons.org/licenses/by-sa/4.0/',
    'http://creativecommons.org/licenses/zero/1.0/',
    'https://creativecommons.org/licenses/zero/1.0/',
  };

  @override
  String get id => 'internet-archive';

  @override
  Future<PlaybackResolution> resolve(PlaybackRequest request) async {
    if (request.kind != PlaybackMediaKind.movie ||
        request.title.trim().isEmpty) {
      return PlaybackResolution(
        providerId: id,
        variants: const [],
        message: 'Internet Archive поддерживается здесь только для фильмов.',
      );
    }

    final query = 'title:"${_escapeQuery(request.title.trim())}" AND mediatype:movies';
    final searchUri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': query,
      'fl[]': 'identifier,title,year',
      'rows': '8',
      'page': '1',
      'output': 'json',
    });

    try {
      final searchResponse = await _client
          .get(searchUri, headers: const {'User-Agent': 'OMNI_AI/1.0'})
          .timeout(const Duration(seconds: 10));
      if (searchResponse.statusCode != 200) {
        return PlaybackResolution(
          providerId: id,
          variants: const [],
          message: 'Каталог Internet Archive временно недоступен.',
        );
      }

      final searchJson = jsonDecode(searchResponse.body);
      final docs = searchJson is Map
          ? (searchJson['response'] is Map
                ? (searchJson['response'] as Map)['docs']
                : null)
          : null;
      if (docs is! List) {
        return PlaybackResolution(providerId: id, variants: const []);
      }

      final variants = <PlaybackVariant>[];
      for (final raw in docs.take(8)) {
        if (raw is! Map || raw['identifier'] is! String) continue;
        final identifier = (raw['identifier'] as String).trim();
        if (identifier.isEmpty ||
            !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(identifier)) {
          continue;
        }

        final metadataUri = Uri.https('archive.org', '/metadata/$identifier');
        final metadataResponse = await _client
            .get(metadataUri, headers: const {'User-Agent': 'OMNI_AI/1.0'})
            .timeout(const Duration(seconds: 10));
        if (metadataResponse.statusCode != 200) continue;

        final metadata = jsonDecode(metadataResponse.body);
        if (metadata is! Map) continue;
        final meta = metadata['metadata'];
        if (meta is! Map) continue;
        final license = (meta['licenseurl'] ?? '').toString().trim();
        if (!_openLicenses.contains(license)) continue;

        final files = metadata['files'];
        if (files is! List) continue;
        for (final file in files) {
          if (file is! Map || file['name'] is! String) continue;
          final name = (file['name'] as String).trim();
          final lower = name.toLowerCase();
          if (!(lower.endsWith('.mp4') ||
              lower.endsWith('.m4v') ||
              lower.endsWith('.webm'))) {
            continue;
          }
          if (file['private'] == 'true' ||
              file['source'] == 'metadata' ||
              (file['size'] != null &&
                  int.tryParse(file['size'].toString()) == 0)) {
            continue;
          }

          final encodedName = name
              .split('/')
              .map(Uri.encodeComponent)
              .join('/');
          final streamUri = Uri.https(
            'archive.org',
            '/download/$identifier/$encodedName',
          );
          variants.add(
            PlaybackVariant(
              url: streamUri.toString(),
              quality: _qualityFromName(name),
              format: lower.endsWith('.webm') ? 'webm' : 'mp4',
            ),
          );
          if (variants.length >= 4) break;
        }
        if (variants.length >= 4) break;
      }

      return PlaybackResolution(
        providerId: id,
        variants: variants,
        message: variants.isEmpty
            ? 'Не найден фильм с подтверждённой открытой лицензией.'
            : null,
      );
    } on Object {
      return PlaybackResolution(
        providerId: id,
        variants: const [],
        message: 'Ошибка поиска видео в Internet Archive.',
      );
    }
  }

  String _escapeQuery(String value) =>
      value.replaceAll(r'\\', r'\\\\').replaceAll('"', r'\"');

  String _qualityFromName(String name) {
    final match = RegExp(r'(2160|1440|1080|720|480)p', caseSensitive: false)
        .firstMatch(name);
    return match == null ? 'Auto' : '${match.group(1)}p';
  }
}
