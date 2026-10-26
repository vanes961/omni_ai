import 'package:omni_ai/features/media/data/video_source_provider.dart';

/// Describes what a discovered site can provide. Catalog metadata alone is
/// never treated as a playable stream.
enum DiscoveredSourceCapability {
  metadata,
  episodeIndex,
  trailer,
  playback,
}

/// Current health of a discovered source.
enum DiscoveredSourceStatus { unverified, available, unavailable, rejected }

/// A candidate found by a discovery adapter. The discovery layer does not
/// assume that a website is safe, legal, or capable of playback.
class DiscoveredSourceCandidate {
  const DiscoveredSourceCandidate({
    required this.id,
    required this.name,
    required this.baseUri,
    required this.mediaKinds,
    required this.capabilities,
    required this.discoveredBy,
    this.status = DiscoveredSourceStatus.unverified,
    this.checkedAt,
    this.note,
  });

  final String id;
  final String name;
  final Uri baseUri;
  final Set<PlaybackMediaKind> mediaKinds;
  final Set<DiscoveredSourceCapability> capabilities;
  final String discoveredBy;
  final DiscoveredSourceStatus status;
  final DateTime? checkedAt;
  final String? note;

  bool get hasValidWebAddress =>
      (baseUri.scheme == 'https' || baseUri.scheme == 'http') &&
      baseUri.host.isNotEmpty &&
      baseUri.userInfo.isEmpty;

  DiscoveredSourceCandidate copyWith({
    DiscoveredSourceStatus? status,
    DateTime? checkedAt,
    String? note,
  }) =>
      DiscoveredSourceCandidate(
        id: id,
        name: name,
        baseUri: baseUri,
        mediaKinds: mediaKinds,
        capabilities: capabilities,
        discoveredBy: discoveredBy,
        status: status ?? this.status,
        checkedAt: checkedAt ?? this.checkedAt,
        note: note ?? this.note,
      );
}

/// Plug-in boundary for search engines, public registries, or curated
/// discovery feeds. Each adapter can be added without editing the player.
abstract interface class SourceDiscoveryAdapter {
  String get id;

  Future<Iterable<DiscoveredSourceCandidate>> discover({
    required Set<PlaybackMediaKind> mediaKinds,
  });
}

/// Separates discovery from validation. A search result is only a candidate
/// until it passes policy checks and a provider-specific capability probe.
abstract interface class DiscoveredSourceProbe {
  Future<DiscoveredSourceCandidate> check(
    DiscoveredSourceCandidate candidate,
  );
}

/// Coordinates discovery adapters and maintains the latest candidate list.
///
/// This registry is intentionally in-memory in the first iteration. Durable
/// storage and scheduled background refresh should be added after a concrete
/// discovery adapter and its data policy are selected.
class SourceDiscoveryService {
  SourceDiscoveryService({
    required Iterable<SourceDiscoveryAdapter> adapters,
    required DiscoveredSourceProbe probe,
  }) : _adapters = List<SourceDiscoveryAdapter>.unmodifiable(adapters),
       _probe = probe;

  final List<SourceDiscoveryAdapter> _adapters;
  final DiscoveredSourceProbe _probe;
  final Map<String, DiscoveredSourceCandidate> _candidates = {};

  List<DiscoveredSourceCandidate> get candidates =>
      List<DiscoveredSourceCandidate>.unmodifiable(_candidates.values);

  List<String> get adapterIds =>
      List<String>.unmodifiable(_adapters.map((adapter) => adapter.id));

  Future<List<DiscoveredSourceCandidate>> discoverAndCheck({
    Set<PlaybackMediaKind> mediaKinds = const {
      PlaybackMediaKind.movie,
      PlaybackMediaKind.series,
      PlaybackMediaKind.anime,
    },
  }) async {
    for (final adapter in _adapters) {
      Iterable<DiscoveredSourceCandidate> discovered;
      try {
        discovered = await adapter.discover(mediaKinds: mediaKinds);
      } on Object {
        // A failed discovery backend must not block other backends.
        continue;
      }

      for (final candidate in discovered) {
        if (!candidate.hasValidWebAddress ||
            candidate.id.trim().isEmpty ||
            candidate.name.trim().isEmpty ||
            candidate.discoveredBy != adapter.id) {
          _candidates[candidate.id] = candidate.copyWith(
            status: DiscoveredSourceStatus.rejected,
            checkedAt: DateTime.now(),
            note: 'Некорректный адрес или метаданные источника.',
          );
          continue;
        }

        try {
          final checked = await _probe.check(candidate);
          _candidates[candidate.id] = checked;
        } on Object {
          _candidates[candidate.id] = candidate.copyWith(
            status: DiscoveredSourceStatus.unavailable,
            checkedAt: DateTime.now(),
            note: 'Проверка источника завершилась ошибкой.',
          );
        }
      }
    }
    return candidates;
  }

  /// Allows a caller to disable a source without deleting discovery history.
  void reject(String candidateId, {String? reason}) {
    final candidate = _candidates[candidateId];
    if (candidate == null) return;
    _candidates[candidateId] = candidate.copyWith(
      status: DiscoveredSourceStatus.rejected,
      checkedAt: DateTime.now(),
      note: reason ?? 'Источник отключён.',
    );
  }

  void clear() => _candidates.clear();
}
