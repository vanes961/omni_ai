import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omni_ai/features/media/data/source_discovery_service.dart';
import 'package:omni_ai/features/media/data/video_source_provider.dart';

/// Discovers PeerTube via its public directory instead of a hand-written list.
class PeerTubeDirectoryDiscoveryAdapter implements SourceDiscoveryAdapter {
  @override
  String get id => 'peertube-directory';

  @override
  Future<Iterable<DiscoveredSourceCandidate>> discover({
    required Set<PlaybackMediaKind> mediaKinds,
  }) async {
    if (mediaKinds.isEmpty) return const <DiscoveredSourceCandidate>[];
    return [
      DiscoveredSourceCandidate(
        id: id,
        name: 'PeerTube (открытые видео сообщества)',
        baseUri: Uri.https('instances.joinpeertube.org', '/'),
        mediaKinds: mediaKinds,
        capabilities: const {DiscoveredSourceCapability.playback},
        discoveredBy: id,
        note:
            'Поиск по публичному каталогу; лицензия и видеопоток проверяются отдельно.',
      ),
    ];
  }
}

class PeerTubeDirectoryProbe implements DiscoveredSourceProbe {
  PeerTubeDirectoryProbe({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<DiscoveredSourceCandidate> check(
    DiscoveredSourceCandidate candidate,
  ) async {
    if (candidate.id != 'peertube-directory' ||
        candidate.baseUri.scheme != 'https' ||
        candidate.baseUri.host != 'instances.joinpeertube.org') {
      return candidate.copyWith(
        status: DiscoveredSourceStatus.rejected,
        checkedAt: DateTime.now(),
        note: 'Неизвестный адрес каталога PeerTube.',
      );
    }
    try {
      final response = await _client
          .get(
            Uri.https('instances.joinpeertube.org', '/api/v1/instances', {
              'start': '0',
              'count': '1',
            }),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));
      final decoded = response.statusCode == 200
          ? jsonDecode(response.body)
          : null;
      final data = decoded is Map ? decoded['data'] : null;
      final valid =
          data is List &&
          data.any((item) => item is Map && _validHost(item['host']));
      return candidate.copyWith(
        status: valid
            ? DiscoveredSourceStatus.available
            : DiscoveredSourceStatus.unavailable,
        checkedAt: DateTime.now(),
        note: valid
            ? 'Каталог доступен; конкретные серверы проверяются при поиске.'
            : 'Каталог не вернул список серверов.',
      );
    } on Object {
      return candidate.copyWith(
        status: DiscoveredSourceStatus.unavailable,
        checkedAt: DateTime.now(),
        note: 'Каталог PeerTube временно недоступен.',
      );
    }
  }
}

/// Searches a small set of public PeerTube instances and returns only streams
/// with an explicit permissive licence. This is not a commercial movie index.
class PeerTubeDirectoryPlaybackProvider implements VideoSourceProvider {
  PeerTubeDirectoryPlaybackProvider({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const _acceptedLicenceIds = {1, 2, 7, 8};
  static const _directoryHost = 'instances.joinpeertube.org';

  @override
  String get id => 'peertube-directory';

  @override
  Future<PlaybackResolution> resolve(PlaybackRequest request) async {
    if (request.title.trim().isEmpty) {
      return PlaybackResolution(
        providerId: id,
        variants: const [],
        message: 'Для поиска видео нужно название.',
      );
    }
    try {
      final directoryResponse = await _client
          .get(
            Uri.https(_directoryHost, '/api/v1/instances', {
              'start': '0',
              'count': '20',
            }),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));
      if (directoryResponse.statusCode != 200) return _unavailable();

      final decoded = jsonDecode(directoryResponse.body);
      final rawInstances = decoded is Map ? decoded['data'] : null;
      if (rawInstances is! List) return _unavailable();

      final hosts = <String>[];
      for (final raw in rawInstances) {
        if (raw is! Map) continue;
        final host = raw['host'];
        final totalVideos = int.tryParse(raw['totalVideos']?.toString() ?? '');
        if (!_validHost(host) || (totalVideos != null && totalVideos <= 0)) {
          continue;
        }
        final normalized = (host as String).toLowerCase();
        if (!hosts.contains(normalized)) hosts.add(normalized);
        if (hosts.length >= 5) break;
      }
      if (hosts.isEmpty) {
        return PlaybackResolution(providerId: id, variants: const []);
      }

      final results = await Future.wait(
        hosts.map((host) async {
          // Prefer Russian-language results for the user's primary locale.
          // Fall back to the instance's broader search when no licensed,
          // directly playable Russian-language result is available.
          final russian = await _searchInstance(
            host,
            request.title.trim(),
            language: 'ru',
          );
          if (russian.isNotEmpty) return russian;
          return _searchInstance(host, request.title.trim());
        }),
      );
      final variants = <String, PlaybackVariant>{};
      for (final result in results) {
        for (final variant in result) {
          variants.putIfAbsent(variant.url, () => variant);
        }
      }
      return PlaybackResolution(
        providerId: id,
        variants: variants.values,
        message: variants.isEmpty
            ? 'В PeerTube не найден подходящий открыто лицензированный видеопоток.'
            : null,
      );
    } on Object {
      return _unavailable();
    }
  }

  Future<List<PlaybackVariant>> _searchInstance(
    String host,
    String title, {
    String? language,
  }) async {
    try {
      final response = await _client
          .get(
            Uri.https(host, '/api/v1/search/videos', {
              'search': title,
              'count': '5',
              'sort': '-views',
              'nsfw': 'false',
              'languageOneOf': ?language,
            }),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      final data = decoded is Map ? decoded['data'] : null;
      if (data is! List) return const [];

      final variants = <PlaybackVariant>[];
      for (final raw in data) {
        if (raw is! Map || !_hasAcceptedLicence(raw['licence'])) continue;

        final files = raw['files'];
        if (files is List) {
          for (final file in files) {
            if (file is! Map) continue;
            final url = _sameHostHttpsUrl(file['fileUrl'], host);
            if (url == null || !_isVideoUrl(url)) continue;
            variants.add(
              PlaybackVariant(
                url: url.toString(),
                quality: _quality(file['resolution']),
                format: _format(url),
              ),
            );
          }
        }

        final playlists = raw['streamingPlaylists'];
        if (playlists is List) {
          for (final playlist in playlists) {
            if (playlist is! Map) continue;
            final url = _sameHostHttpsUrl(playlist['playlistUrl'], host);
            if (url == null || !url.path.toLowerCase().endsWith('.m3u8')) {
              continue;
            }
            variants.add(
              PlaybackVariant(
                url: url.toString(),
                quality: 'Auto',
                format: 'hls',
              ),
            );
          }
        }
      }
      return variants;
    } on Object {
      return const [];
    }
  }

  bool _hasAcceptedLicence(Object? raw) {
    if (raw is! Map) return false;
    final id = int.tryParse(raw['id']?.toString() ?? '');
    return id != null && _acceptedLicenceIds.contains(id);
  }

  Uri? _sameHostHttpsUrl(Object? raw, String expectedHost) {
    if (raw is! String || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != expectedHost ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  bool _isVideoUrl(Uri uri) {
    final path = uri.path.toLowerCase();
    return const ['.mp4', '.webm', '.ogv', '.ogg', '.m3u8'].any(path.endsWith);
  }

  String? _quality(Object? raw) {
    if (raw is! Map) return null;
    final label = raw['label'];
    if (label is String && label.trim().isNotEmpty) return label.trim();
    final id = int.tryParse(raw['id']?.toString() ?? '');
    return id == null || id <= 0 ? null : '${id}p';
  }

  String _format(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.endsWith('.m3u8')) return 'hls';
    if (path.endsWith('.webm')) return 'webm';
    if (path.endsWith('.ogv') || path.endsWith('.ogg')) return 'ogg';
    return 'mp4';
  }

  PlaybackResolution _unavailable() => PlaybackResolution(
    providerId: id,
    variants: const [],
    message: 'Каталог PeerTube временно недоступен.',
  );
}

bool _validHost(Object? raw) {
  if (raw is! String) return false;
  final host = raw.trim().toLowerCase();
  if (host.isEmpty ||
      host.length > 253 ||
      host.contains('://') ||
      host.contains('/') ||
      host.contains('@') ||
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.startsWith('127.') ||
      host.startsWith('10.') ||
      host.startsWith('192.168.') ||
      host.startsWith('169.254.') ||
      RegExp(r'^172\.(1[6-9]|2[0-9]|3[01])\..+').hasMatch(host) ||
      RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$').hasMatch(host)) {
    return false;
  }
  return RegExp(
    r'^(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$',
  ).hasMatch(host);
}
