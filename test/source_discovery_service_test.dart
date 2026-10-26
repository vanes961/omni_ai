import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/data/source_discovery_service.dart';
import 'package:omni_ai/features/media/data/video_source_engine.dart';
import 'package:omni_ai/features/media/data/video_source_provider.dart';

void main() {
  group('SourceDiscoveryService', () {
    test('discovers and records a valid catalog candidate', () async {
      final service = SourceDiscoveryService(
        adapters: [_FakeAdapter([_candidate()])],
        probe: _FakeProbe(
          (candidate) => candidate.copyWith(
            status: DiscoveredSourceStatus.available,
            checkedAt: DateTime.utc(2026, 10, 26),
          ),
        ),
      );

      final results = await service.discoverAndCheck();

      expect(results, hasLength(1));
      expect(results.single.status, DiscoveredSourceStatus.available);
      expect(service.candidates.single.id, 'demo-source');
    });

    test('registers only checked playback-capable providers with the engine',
        () async {
      final engine = VideoSourceEngine([]);
      final service = SourceDiscoveryService(
        adapters: [
          _FakeAdapter([
            _candidate(id: 'metadata-only'),
            _candidate(
              id: 'playback-source',
              capabilities: const {DiscoveredSourceCapability.playback},
            ),
          ]),
        ],
        probe: _FakeProbe(
          (candidate) => candidate.copyWith(
            status: DiscoveredSourceStatus.available,
          ),
        ),
        videoSourceEngine: engine,
        providerFactory: (candidate) => _FakeVideoProvider(candidate.id),
      );

      await service.discoverAndCheck();

      expect(engine.providerIds, ['playback-source']);
    });

    test('rejects invalid addresses before probing', () async {
      var probed = false;
      final service = SourceDiscoveryService(
        adapters: [
          _FakeAdapter([
            _candidate(uri: Uri.parse('javascript:alert(1)')),
          ]),
        ],
        probe: _FakeProbe((candidate) {
          probed = true;
          return candidate;
        }),
      );

      final results = await service.discoverAndCheck();

      expect(probed, isFalse);
      expect(results.single.status, DiscoveredSourceStatus.rejected);
    });

    test('continues when one discovery adapter fails', () async {
      final service = SourceDiscoveryService(
        adapters: [
          _ThrowingAdapter(),
          _FakeAdapter([_candidate(id: 'second-source')]),
        ],
        probe: _FakeProbe(
          (candidate) => candidate.copyWith(
            status: DiscoveredSourceStatus.available,
          ),
        ),
      );

      final results = await service.discoverAndCheck();

      expect(results.map((candidate) => candidate.id), ['second-source']);
    });

    test('rejecting a registered source unregisters it from the engine',
        () async {
      final engine = VideoSourceEngine([]);
      final service = SourceDiscoveryService(
        adapters: [
          _FakeAdapter([
            _candidate(
              capabilities: const {DiscoveredSourceCapability.playback},
            ),
          ]),
        ],
        probe: _FakeProbe(
          (candidate) => candidate.copyWith(
            status: DiscoveredSourceStatus.available,
          ),
        ),
        videoSourceEngine: engine,
        providerFactory: (candidate) => _FakeVideoProvider(candidate.id),
      );
      await service.discoverAndCheck();

      service.reject('demo-source', reason: 'Отключён вручную');

      expect(service.candidates.single.status, DiscoveredSourceStatus.rejected);
      expect(service.candidates.single.note, 'Отключён вручную');
      expect(engine.providerIds, isEmpty);
    });
  });
}

DiscoveredSourceCandidate _candidate({
  String id = 'demo-source',
  Uri? uri,
  Set<DiscoveredSourceCapability> capabilities = const {
    DiscoveredSourceCapability.metadata,
  },
}) =>
    DiscoveredSourceCandidate(
      id: id,
      name: 'Demo source',
      baseUri: uri ?? Uri.parse('https://example.org'),
      mediaKinds: const {PlaybackMediaKind.movie},
      capabilities: capabilities,
      discoveredBy: 'fake-adapter',
    );

class _FakeAdapter implements SourceDiscoveryAdapter {
  _FakeAdapter(this.results);

  final Iterable<DiscoveredSourceCandidate> results;

  @override
  String get id => 'fake-adapter';

  @override
  Future<Iterable<DiscoveredSourceCandidate>> discover({
    required Set<PlaybackMediaKind> mediaKinds,
  }) async => results;
}

class _ThrowingAdapter implements SourceDiscoveryAdapter {
  @override
  String get id => 'throwing-adapter';

  @override
  Future<Iterable<DiscoveredSourceCandidate>> discover({
    required Set<PlaybackMediaKind> mediaKinds,
  }) async {
    throw Exception('discovery backend unavailable');
  }
}

class _FakeProbe implements DiscoveredSourceProbe {
  _FakeProbe(this.resolve);

  final DiscoveredSourceCandidate Function(DiscoveredSourceCandidate)
      resolve;

  @override
  Future<DiscoveredSourceCandidate> check(
    DiscoveredSourceCandidate candidate,
  ) async => resolve(candidate);
}

class _FakeVideoProvider implements VideoSourceProvider {
  _FakeVideoProvider(this.id);

  @override
  final String id;

  @override
  Future<PlaybackResolution> resolve(PlaybackRequest request) async =>
      PlaybackResolution(providerId: id, variants: const []);
}
