import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omni_ai/features/media/data/source_discovery_service.dart';
import 'package:omni_ai/features/media/data/video_source_provider.dart';

/// Discovers Wikimedia Commons as a source of openly licensed video files.
/// Commons is a public media archive, not a catalogue of commercial films.
class WikimediaCommonsDiscoveryAdapter implements SourceDiscoveryAdapter {
  @override
  String get id => 'wikimedia-commons';

  @override
  Future<Iterable<DiscoveredSourceCandidate>> discover({
    required Set<PlaybackMediaKind> mediaKinds,
  }) async {
    if (!mediaKinds.any(
      (kind) => kind == PlaybackMediaKind.movie || kind == PlaybackMediaKind.anime,
    )) {
      return const <DiscoveredSourceCandidate>[];
    }
    return [
      DiscoveredSourceCandidate(
        id: id,
        name: 'Wikimedia Commons (видео с открытой лицензией)',
        baseUri: Uri.https('commons.wikimedia.org', '/'),
        mediaKinds: const {PlaybackMediaKind.movie, PlaybackMediaKind.anime},
        capabilities: const {DiscoveredSourceCapability.playback},
        discoveredBy: id,
        note: 'Архив свободных медиафайлов; это не каталог коммерческих релизов.',
      ),
    ];
  }
}

/// Provider-specific health check for Wikimedia Commons.
class WikimediaCommonsSourceProbe implements DiscoveredSourceProbe {
  WikimediaCommonsSourceProbe({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<DiscoveredSourceCandidate> check(
    DiscoveredSourceCandidate candidate,
  ) async {
    if (candidate.id != 'wikimedia-commons' ||
        candidate.baseUri.host != 'commons.wikimedia.org' ||
        candidate.baseUri.scheme != 'https') {
      return candidate.copyWith(
        status: DiscoveredSourceStatus.rejected,
        checkedAt: DateTime.now(),
        note: 'Неизвестный адрес источника.',
      );
    }

    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'meta': 'siteinfo',
      'format': 'json',
    });
    final response = await _client.get(uri, headers: const {
      'User-Agent': 'OMNI_AI/1.0 (open media discovery)',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 8));

    final available = response.statusCode >= 200 &&
        response.statusCode < 300 &&
        response.body.isNotEmpty;
    return candidate.copyWith(
      status: available
          ? DiscoveredSourceStatus.available
          : DiscoveredSourceStatus.unavailable,
      checkedAt: DateTime.now(),
      note: available
          ? 'API доступен; каждый файл отдельно проверяется по лицензии.'
          : 'API вернул HTTP ${response.statusCode}.',
    );
  }
}

/// Resolves only direct Wikimedia video files whose metadata declares a
/// recognized free license. This provider never treats a search page as video.
class WikimediaCommonsPlaybackProvider implements VideoSourceProvider {
  WikimediaCommonsPlaybackProvider({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const _allowedLicenseFragments = <String>[
    'creativecommons.org/licenses/by/',
    'creativecommons.org/licenses/by-sa/',
    'creativecommons.org/publicdomain/zero/',
    'creativecommons.org/publicdomain/mark/',
    'creativecommons.org/licenses/zero/',
    'public domain',
    'cc0',
  ];

  @override
  String get id => 'wikimedia-commons';

  @override
  Future<PlaybackResolution> resolve(PlaybackRequest request) async {
    if (request.title.trim().isEmpty) {
      return PlaybackResolution(
        providerId: id,
        variants: const [],
        message: 'Для поиска видео нужно название.',
      );
    }

    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'generator': 'search',
      'gsrsearch': 'filetype:video ${request.title.trim()}',
      'gsrnamespace': '6',
      'gsrlimit': '10',
      'prop': 'imageinfo',
      'iiprop': 'url|extmetadata',
      'format': 'json',
    });

    try {
      final response = await _client.get(uri, headers: const {
        'User-Agent': 'OMNI_AI/1.0 (open media discovery)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return PlaybackResolution(
          providerId: id,
          variants: const [],
          message: 'Wikimedia Commons временно недоступен.',
        );
      }

      final decoded = jsonDecode(response.body);
      final query = decoded is Map ? decoded['query'] : null;
      final pages = query is Map ? query['pages'] : null;
      if (pages is! Map) {
        return PlaybackResolution(providerId: id, variants: const []);
      }

      final variants = <PlaybackVariant>[];
      for (final rawPage in pages.values) {
        if (rawPage is! Map) continue;
        final infoList = rawPage['imageinfo'];
        if (infoList is! List || infoList.isEmpty || infoList.first is! Map) {
          continue;
        }
        final info = infoList.first as Map;
        final rawUrl = info['url'];
        if (rawUrl is! String) continue;
        final videoUri = Uri.tryParse(rawUrl);
        if (videoUri == null ||
            videoUri.scheme != 'https' ||
            videoUri.host != 'upload.wikimedia.org' ||
            !_isVideoPath(videoUri.path)) {
          continue;
        }

        final metadata = info['extmetadata'];
        if (metadata is! Map || !_hasAllowedLicense(metadata)) continue;
        variants.add(PlaybackVariant(
          url: videoUri.toString(),
          format: _format(videoUri.path),
          quality: 'Auto',
        ));
        if (variants.length >= 5) break;
      }

      return PlaybackResolution(
        providerId: id,
        variants: variants,
        message: variants.isEmpty
            ? 'Не найдено видео с подтверждённой открытой лицензией.'
            : null,
      );
    } on Object {
      return PlaybackResolution(
        providerId: id,
        variants: const [],
        message: 'Ошибка поиска видео в Wikimedia Commons.',
      );
    }
  }

  bool _hasAllowedLicense(Map metadata) {
    final licenseUrl = _metadataValue(metadata['LicenseUrl']).toLowerCase();
    final licenseShortName =
        _metadataValue(metadata['LicenseShortName']).toLowerCase();
    final combined = '$licenseUrl $licenseShortName';
    return _allowedLicenseFragments.any(combined.contains);
  }

  String _metadataValue(Object? value) {
    if (value is Map) return (value['value'] ?? '').toString().trim();
    return '';
  }

  bool _isVideoPath(String path) {
    final lower = path.toLowerCase();
    return const ['.webm', '.ogv', '.ogg', '.mp4']
        .any(lower.endsWith);
  }

  String _format(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.webm')) return 'webm';
    if (lower.endsWith('.ogv') || lower.endsWith('.ogg')) return 'ogg';
    if (lower.endsWith('.mp4')) return 'mp4';
    return 'video';
  }
}

/// Routes discovery health checks to the probe registered for each known
/// source. Unknown source IDs are rejected instead of being trusted by default.
class CompositeDiscoveredSourceProbe implements DiscoveredSourceProbe {
  CompositeDiscoveredSourceProbe(Map<String, DiscoveredSourceProbe> probes)
    : _probes = Map<String, DiscoveredSourceProbe>.unmodifiable(probes);

  final Map<String, DiscoveredSourceProbe> _probes;

  @override
  Future<DiscoveredSourceCandidate> check(
    DiscoveredSourceCandidate candidate,
  ) async {
    final probe = _probes[candidate.id];
    if (probe == null) {
      return candidate.copyWith(
        status: DiscoveredSourceStatus.rejected,
        checkedAt: DateTime.now(),
        note: 'Для источника не настроена проверка доступности.',
      );
    }
    return probe.check(candidate);
  }
}
