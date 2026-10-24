import 'package:omni_ai/features/media/sources/media_source.dart';

/// Health state for a source. This is runtime state; it is intentionally
/// separate from source configuration so it can later be persisted locally.
enum SourceAvailability { unknown, available, degraded, unavailable }

/// Safe, compact health data for diagnostics. Never stores response bodies,
/// credentials, or full request URLs.
class SourceHealth {
  const SourceHealth({
    required this.sourceId,
    this.availability = SourceAvailability.unknown,
    this.lastCheckedAt,
    this.lastSuccessAt,
    this.consecutiveFailures = 0,
    this.lastErrorCategory,
    this.lastLatency,
  });

  final String sourceId;
  final SourceAvailability availability;
  final DateTime? lastCheckedAt;
  final DateTime? lastSuccessAt;
  final int consecutiveFailures;
  final String? lastErrorCategory;
  final Duration? lastLatency;
}

/// In-memory source registry. State can be persisted to local storage later;
/// no server or paid service is required.
class SourceRegistry {
  SourceRegistry(Iterable<MediaSource> sources)
    : _sources = List<MediaSource>.unmodifiable(sources) {
    for (final source in _sources) {
      _health.putIfAbsent(source.id, () => SourceHealth(sourceId: source.id));
    }
  }

  final List<MediaSource> _sources;
  final Map<String, SourceHealth> _health = {};

  List<MediaSource> get sources => _sources;
  List<SourceHealth> get health =>
      List<SourceHealth>.unmodifiable(_health.values);

  SourceHealth? healthFor(String sourceId) => _health[sourceId];

  List<MediaSource> candidatesFor(MediaSourceKind kind) =>
      List<MediaSource>.unmodifiable(
        _sources.where((source) => source.supportedKinds.contains(kind)),
      );

  void recordSuccess(
    String sourceId, {
    required DateTime checkedAt,
    required Duration latency,
  }) {
    final previous = _health[sourceId];
    if (previous == null) return;
    _health[sourceId] = SourceHealth(
      sourceId: sourceId,
      availability: SourceAvailability.available,
      lastCheckedAt: checkedAt,
      lastSuccessAt: checkedAt,
      consecutiveFailures: 0,
      lastLatency: latency,
    );
  }

  void recordFailure(
    String sourceId, {
    required DateTime checkedAt,
    required String errorCategory,
    Duration? latency,
  }) {
    final previous = _health[sourceId];
    if (previous == null) return;
    final failures = previous.consecutiveFailures + 1;
    _health[sourceId] = SourceHealth(
      sourceId: sourceId,
      availability: failures >= 3
          ? SourceAvailability.unavailable
          : SourceAvailability.degraded,
      lastCheckedAt: checkedAt,
      lastSuccessAt: previous.lastSuccessAt,
      consecutiveFailures: failures,
      lastErrorCategory: _safeCategory(errorCategory),
      lastLatency: latency,
    );
  }

  String _safeCategory(String value) {
    final normalized = value.trim().toLowerCase();
    const allowed = {
      'timeout',
      'network',
      'http',
      'parse',
      'unknown',
    };
    return allowed.contains(normalized) ? normalized : 'unknown';
  }
}
