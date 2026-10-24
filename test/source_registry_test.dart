import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/sources/media_source.dart';
import 'package:omni_ai/features/media/sources/source_registry.dart';

void main() {
  group('SourceRegistry', () {
    test('registers sources as unknown and filters by media kind', () {
      final registry = SourceRegistry([_Source('anime', MediaSourceKind.anime)]);

      expect(registry.healthFor('anime')?.availability, SourceAvailability.unknown);
      expect(registry.candidatesFor(MediaSourceKind.anime), hasLength(1));
      expect(registry.candidatesFor(MediaSourceKind.movie), isEmpty);
    });

    test('marks first failures degraded and repeated failures unavailable', () {
      final registry = SourceRegistry([_Source('catalog', MediaSourceKind.movie)]);
      final now = DateTime.utc(2026, 1, 1);

      registry.recordFailure('catalog', checkedAt: now, errorCategory: 'timeout');
      expect(registry.healthFor('catalog')?.availability, SourceAvailability.degraded);
      registry.recordFailure('catalog', checkedAt: now, errorCategory: 'timeout');
      registry.recordFailure('catalog', checkedAt: now, errorCategory: 'timeout');

      final health = registry.healthFor('catalog')!;
      expect(health.availability, SourceAvailability.unavailable);
      expect(health.consecutiveFailures, 3);
      expect(health.lastErrorCategory, 'timeout');
    });

    test('success restores availability and clears consecutive failures', () {
      final registry = SourceRegistry([_Source('catalog', MediaSourceKind.movie)]);
      final now = DateTime.utc(2026, 1, 1);
      registry.recordFailure('catalog', checkedAt: now, errorCategory: 'network');
      registry.recordSuccess(
        'catalog',
        checkedAt: now.add(const Duration(seconds: 1)),
        latency: const Duration(milliseconds: 180),
      );

      final health = registry.healthFor('catalog')!;
      expect(health.availability, SourceAvailability.available);
      expect(health.consecutiveFailures, 0);
      expect(health.lastErrorCategory, isNull);
      expect(health.lastLatency, const Duration(milliseconds: 180));
    });

    test('does not expose arbitrary error strings in diagnostics', () {
      final registry = SourceRegistry([_Source('catalog', MediaSourceKind.movie)]);
      registry.recordFailure(
        'catalog',
        checkedAt: DateTime.utc(2026),
        errorCategory: 'token=secret-and-verbose-error',
      );
      expect(registry.healthFor('catalog')?.lastErrorCategory, 'unknown');
    });
  });
}

class _Source implements MediaSource {
  _Source(this.id, this.kind);

  @override
  final String id;
  final MediaSourceKind kind;

  @override
  Set<MediaSourceKind> get supportedKinds => {kind};

  @override
  Future<List<MediaItem>> search(String query, {required MediaSourceKind kind}) async =>
      const [];
}
