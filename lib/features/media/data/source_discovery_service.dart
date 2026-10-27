import 'package:omni_ai/features/media/data/video_source_engine.dart';
import 'package:omni_ai/features/media/data/video_source_provider.dart';

/// Describes what a discovered site can provide. Catalog metadata alone is
/// never treated as a playable stream.
enum DiscoveredSourceCapability { metadata, episodeIndex, trailer, playback }

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
  }) => DiscoveredSourceCandidate(
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
  Future<DiscoveredSourceCandidate> check(DiscoveredSourceCandidate candidate);
}

typedef DiscoveredProviderFactory =
    VideoSourceProvider? Function(DiscoveredSourceCandidate candidate);

/// Coordinates discovery, validation, registration, and runtime status.
///
/// Catalog-only candidates are recorded here but are never registered with the
/// playback engine. A playback provider is registered only after a successful
/// probe and an explicit provider factory has produced a matching adapter.
class SourceDiscoveryService {
  SourceDiscoveryService({
    required Iterable<SourceDiscoveryAdapter> adapters,
    required this.probe,
    this.videoSourceEngine,
    this.providerFactory,
  }) : _adapters = List<SourceDiscoveryAdapter>.unmodifiable(adapters);

  final List<SourceDiscoveryAdapter> _adapters;
  final DiscoveredSourceProbe probe;
  final VideoSourceEngine? videoSourceEngine;
  final DiscoveredProviderFactory? providerFactory;
  final Map<String, DiscoveredSourceCandidate> _candidates = {};
  final Set<String> _registeredProviderIds = {};
  final Map<String, String> _manualRejections = {};

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
      // Materialize the complete response inside the guarded block. Some
      // adapters expose lazy iterables that can throw while being iterated.
      // Do not reconcile old entries unless discovery completed successfully.
      List<DiscoveredSourceCandidate> discovered;
      try {
        discovered =
            (await adapter
                    .discover(mediaKinds: mediaKinds)
                    .timeout(const Duration(seconds: 15)))
                .toList(growable: false);
      } on Object {
        // A failed discovery backend must not block other backends or erase
        // its last known candidates after a temporary outage.
        continue;
      }

      final seenIds = discovered.map((candidate) => candidate.id).toSet();
      for (final candidate in discovered) {
        if (!candidate.hasValidWebAddress ||
            candidate.id.trim().isEmpty ||
            candidate.name.trim().isEmpty ||
            candidate.discoveredBy != adapter.id) {
          final rejected = candidate.copyWith(
            status: DiscoveredSourceStatus.rejected,
            checkedAt: DateTime.now(),
            note: 'Некорректный адрес или метаданные источника.',
          );
          _candidates[candidate.id] = rejected;
          _removeRegisteredProvider(candidate.id);
          continue;
        }

        final rejectionReason = _manualRejections[candidate.id];
        if (rejectionReason != null) {
          _candidates[candidate.id] = candidate.copyWith(
            status: DiscoveredSourceStatus.rejected,
            checkedAt: _candidates[candidate.id]?.checkedAt ?? DateTime.now(),
            note: rejectionReason,
          );
          _removeRegisteredProvider(candidate.id);
          continue;
        }

        try {
          final checked = await probe
              .check(candidate)
              .timeout(const Duration(seconds: 12));
          if (checked.id != candidate.id ||
              checked.baseUri != candidate.baseUri ||
              checked.discoveredBy != candidate.discoveredBy) {
            final rejected = candidate.copyWith(
              status: DiscoveredSourceStatus.rejected,
              checkedAt: DateTime.now(),
              note: 'Проверка изменила идентификатор или адрес источника.',
            );
            _candidates[candidate.id] = rejected;
            _removeRegisteredProvider(candidate.id);
            continue;
          }

          // The probe may report health, but it cannot rewrite the identity,
          // URL, supported media, or declared capabilities of the candidate.
          final normalized = candidate.copyWith(
            status: checked.status,
            checkedAt: checked.checkedAt ?? DateTime.now(),
            note: checked.note,
          );
          _candidates[candidate.id] = normalized;
          _syncPlaybackProvider(normalized);
        } on Object {
          final unavailable = candidate.copyWith(
            status: DiscoveredSourceStatus.unavailable,
            checkedAt: DateTime.now(),
            note: 'Проверка источника завершилась ошибкой.',
          );
          _candidates[candidate.id] = unavailable;
          _removeRegisteredProvider(candidate.id);
        }
      }

      // A successful complete scan is authoritative for this adapter. Remove
      // entries it no longer reports, including any playback provider we own.
      final staleIds = _candidates.values
          .where(
            (candidate) =>
                candidate.discoveredBy == adapter.id &&
                !seenIds.contains(candidate.id),
          )
          .map((candidate) => candidate.id)
          .toList(growable: false);
      for (final staleId in staleIds) {
        _candidates.remove(staleId);
        _removeRegisteredProvider(staleId);
      }
    }
    return candidates;
  }

  void _syncPlaybackProvider(DiscoveredSourceCandidate candidate) {
    final engine = videoSourceEngine;
    final factory = providerFactory;
    final canPlay =
        candidate.status == DiscoveredSourceStatus.available &&
        candidate.capabilities.contains(DiscoveredSourceCapability.playback);

    if (!canPlay || engine == null || factory == null) {
      _removeRegisteredProvider(candidate.id);
      return;
    }

    // Do not replace a provider owned by another part of the app. Discovery
    // may update only providers that this service registered itself.
    if (!_registeredProviderIds.contains(candidate.id) &&
        engine.providerIds.contains(candidate.id)) {
      return;
    }

    try {
      final provider = factory(candidate);
      if (provider == null || provider.id != candidate.id) {
        _removeRegisteredProvider(candidate.id);
        return;
      }
      engine.registerProvider(provider);
      _registeredProviderIds.add(candidate.id);
    } on Object {
      _removeRegisteredProvider(candidate.id);
    }
  }

  void _removeRegisteredProvider(String providerId) {
    if (!_registeredProviderIds.remove(providerId)) return;
    videoSourceEngine?.unregisterProvider(providerId);
  }

  /// Allows a caller to disable a source without deleting discovery history.
  void reject(String candidateId, {String? reason}) {
    final candidate = _candidates[candidateId];
    if (candidate == null) return;
    final rejectionReason = reason ?? 'Источник отключён.';
    _manualRejections[candidateId] = rejectionReason;
    _candidates[candidateId] = candidate.copyWith(
      status: DiscoveredSourceStatus.rejected,
      checkedAt: DateTime.now(),
      note: rejectionReason,
    );
    _removeRegisteredProvider(candidateId);
  }

  /// Re-enables a manually rejected source for validation on the next scan.
  void allow(String candidateId) {
    _manualRejections.remove(candidateId);
    final candidate = _candidates[candidateId];
    if (candidate == null || candidate.status != DiscoveredSourceStatus.rejected) {
      return;
    }
    _candidates[candidateId] = candidate.copyWith(
      status: DiscoveredSourceStatus.unverified,
      checkedAt: DateTime.now(),
      note: 'Повторная проверка разрешена.',
    );
  }

  /// Clears discovery history and removes only providers registered here.
  void clear() {
    for (final providerId in _registeredProviderIds.toList()) {
      videoSourceEngine?.unregisterProvider(providerId);
    }
    _registeredProviderIds.clear();
    _manualRejections.clear();
    _candidates.clear();
  }
}
