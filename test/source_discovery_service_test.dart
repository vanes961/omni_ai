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

    test(
      'registers only checked playback-capable providers with the engine',
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
      },
    );

    test('adapter identity mismatch cannot overwrite another source', () async {
      final engine = VideoSourceEngine([]);
      final service = SourceDiscoveryService(
        adapters: [
          _FakeAdapter([
            _candidate(
              id: 'shared-source',
              discoveredBy: 'trusted-adapter',
              capabilities: const {DiscoveredSourceCapability.playback},
            ),
          ], adapterId: 'trusted-adapter'),
          _FakeAdapter([
            _candidate(
              id: 'shared-source',
              discoveredBy: 'trusted-adapter',
              uri: Uri.parse('javascript:alert(1)'),
            ),
          ], adapterId: 'untrusted-adapter'),
        ],
        probe: _FakeProbe(
          (candidate) => candidate.copyWith(
            status: DiscoveredSourceStatus.available,
          ),
        ),
        videoSourceEngine: engine,
        providerFactory: (candidate) => _FakeVideoProvider(candidate.id),
      );

      final results = await service.discoverAndCheck();

      expect(results, hasLength(1));
      expect(results.single.discoveredBy, 'trusted-adapter');
      expect(results.single.status, DiscoveredSourceStatus.available);
      expect(engine.providerIds, ['shared-source']);
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

    test(
      'rejecting a registered source unregisters it from the engine',
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

        expect(
          service.candidates.single.status,
          DiscoveredSourceStatus.rejected,
        );
        expect(service.candidates.single.note, 'Отключён вручную');
        expect(engine.providerIds, isEmpty);
      },
    );

    test('manual rejection persists until the source is allowed again', () async {
      final adapter = _MutableAdapter([
        _candidate(
          capabilities: const {DiscoveredSourceCapability.playback},
        ),
      ]);
      final engine = VideoSourceEngine([]);
      final service = SourceDiscoveryService(
        adapters: [adapter],
        probe: _FakeProbe(
          (candidate) => candidate.copyWith(
            status: DiscoveredSourceStatus.available,
          ),
        ),
        videoSourceEngine: engine,
        providerFactory: (candidate) => _FakeVideoProvider(candidate.id),
      );

      await service.discoverAndCheck();
      service.reject('demo-source', reason: 'Отключён пользователем');
      await service.discoverAndCheck();

      expect(service.candidates.single.status, DiscoveredSourceStatus.rejected);
      expect(service.candidates.single.note, 'Отключён пользователем');
      expect(engine.providerIds, isEmpty);

      service.allow('demo-source');
      await service.discoverAndCheck();

      expect(service.candidates.single.status, DiscoveredSourceStatus.available);
      expect(engine.providerIds, ['demo-source']);
    });

    test('persists manual rejections across service instances', () async {
      final store = _FakeRejectionStore();
      final first = SourceDiscoveryService(
        adapters: [_FakeAdapter([_candidate()])],
        probe: _FakeProbe(
          (candidate) => candidate.copyWith(
            status: DiscoveredSourceStatus.available,
          ),
        ),
        rejectionStore: store,
      );
      await first.discoverAndCheck();
      first.reject('demo-source', reason: 'Отключён пользователем');
      await Future<void>.delayed(Duration.zero);

      final second = SourceDiscoveryService(
        adapters: [_FakeAdapter([_candidate()])],
        probe: _FakeProbe(
          (candidate) => candidate.copyWith(
            status: DiscoveredSourceStatus.available,
          ),
        ),
        rejectionStore: store,
      );
      final results = await second.discoverAndCheck();

      expect(results.single.status, DiscoveredSourceStatus.rejected);
      expect(results.single.note, 'Отключён пользователем');
    });

    test('rejects probe results that change source identity', () async {
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
          (candidate) => DiscoveredSourceCandidate(
            id: 'forged-id',
            name: candidate.name,
            baseUri: Uri.parse('https://example.org'),
            mediaKinds: candidate.mediaKinds,
            capabilities: candidate.capabilities,
            discoveredBy: candidate.discoveredBy,
            status: DiscoveredSourceStatus.available,
          ),
        ),
        videoSourceEngine: engine,
        providerFactory: (candidate) => _FakeVideoProvider(candidate.id),
      );

      final results = await service.discoverAndCheck();

      expect(results.single.status, DiscoveredSourceStatus.rejected);
      expect(engine.providerIds, isEmpty);
    });

    test('unregisters a provider when a source becomes unavailable', () async {
      var status = DiscoveredSourceStatus.available;
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
          (candidate) => candidate.copyWith(status: status),
        ),
        videoSourceEngine: engine,
        providerFactory: (candidate) => _FakeVideoProvider(candidate.id),
      );

      await service.discoverAndCheck();
      expect(engine.providerIds, ['demo-source']);

      status = DiscoveredSourceStatus.unavailable;
      await service.discoverAndCheck();

      expect(engine.providerIds, isEmpty);
    });

    test('unregisters a provider when playback capability is removed',
        () async {
      var capabilities = const {DiscoveredSourceCapability.playback};
      final engine = VideoSourceEngine([]);
      final adapter = _ChangingCapabilityAdapter(() => capabilities);
      final service = SourceDiscoveryService(
        adapters: [adapter],
        probe: _FakeProbe(
          (candidate) => candidate.copyWith(
            status: DiscoveredSourceStatus.available,
          ),
        ),
        videoSourceEngine: engine,
        providerFactory: (candidate) => _FakeVideoProvider(candidate.id),
      );

      await service.discoverAndCheck();
      expect(engine.providerIds, ['demo-source']);

      capabilities = const {DiscoveredSourceCapability.metadata};
      await service.discoverAndCheck();

      expect(engine.providerIds, isEmpty);
    });

    test('probe errors remove stale discovered providers', () async {
      var shouldThrow = false;
      final engine = VideoSourceEngine([]);
      final service = SourceDiscoveryService(
        adapters: [
          _FakeAdapter([
            _candidate(
              capabilities: const {DiscoveredSourceCapability.playback},
            ),
          ]),
        ],
        probe: _FakeProbe((candidate) {
          if (shouldThrow) throw Exception('probe failed');
          return candidate.copyWith(
            status: DiscoveredSourceStatus.available,
          );
        }),
        videoSourceEngine: engine,
        providerFactory: (candidate) => _FakeVideoProvider(candidate.id),
      );

      await service.discoverAndCheck();
      expect(engine.providerIds, ['demo-source']);

      shouldThrow = true;
      await service.discoverAndCheck();

      expect(engine.providerIds, isEmpty);
      expect(
        service.candidates.single.status,
        DiscoveredSourceStatus.unavailable,
      );
    });

    test('removes stale candidates after a successful complete scan', () async {
      final adapter = _MutableAdapter([
        _candidate(
          capabilities: const {DiscoveredSourceCapability.playback},
        ),
      ]);
      final engine = VideoSourceEngine([]);
      final service = SourceDiscoveryService(
        adapters: [adapter],
        probe: _FakeProbe(
          (candidate) => candidate.copyWith(
            status: DiscoveredSourceStatus.available,
          ),
        ),
        videoSourceEngine: engine,
        providerFactory: (candidate) => _FakeVideoProvider(candidate.id),
      );

      await service.discoverAndCheck();
      expect(engine.providerIds, ['demo-source']);

      adapter.results = const [];
      final results = await service.discoverAndCheck();

      expect(results, isEmpty);
      expect(engine.providerIds, isEmpty);
    });

    test('preserves last known candidates when discovery fails', () async {
      final adapter = _MutableAdapter([_candidate()]);
      final service = SourceDiscoveryService(
        adapters: [adapter],
        probe: _FakeProbe(
          (candidate) => candidate.copyWith(
            status: DiscoveredSourceStatus.available,
          ),
        ),
      );

      await service.discoverAndCheck();
      adapter.fail = true;
      final results = await service.discoverAndCheck();

      expect(results, hasLength(1));
      expect(results.single.id, 'demo-source');
      expect(results.single.status, DiscoveredSourceStatus.available);
    });

    test('clear removes only providers registered by discovery', () async {
      final baseProvider = _FakeVideoProvider('base-provider');
      final engine = VideoSourceEngine([baseProvider]);
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
      service.clear();

      expect(engine.providerIds, ['base-provider']);
      expect(service.candidates, isEmpty);
    });
  });
}

DiscoveredSourceCandidate _candidate({
  String id = 'demo-source',
  Uri? uri,
  String discoveredBy = 'fake-adapter',
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
      discoveredBy: discoveredBy,
    );

class _FakeAdapter implements SourceDiscoveryAdapter {
  _FakeAdapter(this.results, {this.adapterId = 'fake-adapter'});

  final Iterable<DiscoveredSourceCandidate> results;
  final String adapterId;

  @override
  String get id => adapterId;

  @override
  Future<Iterable<DiscoveredSourceCandidate>> discover({
    required Set<PlaybackMediaKind> mediaKinds,
  }) async => results;
}

class _MutableAdapter implements SourceDiscoveryAdapter {
  _MutableAdapter(this.results);

  Iterable<DiscoveredSourceCandidate> results;
  bool fail = false;

  @override
  String get id => 'fake-adapter';

  @override
  Future<Iterable<DiscoveredSourceCandidate>> discover({
    required Set<PlaybackMediaKind> mediaKinds,
  }) async {
    if (fail) throw Exception('temporary discovery failure');
    return results;
  }
}

class _ChangingCapabilityAdapter implements SourceDiscoveryAdapter {
  _ChangingCapabilityAdapter(this.capabilities);

  final Set<DiscoveredSourceCapability> Function() capabilities;

  @override
  String get id => 'fake-adapter';

  @override
  Future<Iterable<DiscoveredSourceCandidate>> discover({
    required Set<PlaybackMediaKind> mediaKinds,
  }) async => [
    _candidate(capabilities: capabilities()),
  ];
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

class _FakeRejectionStore implements SourceDiscoveryRejectionStore {
  Map<String, String> values = {};

  @override
  Future<Map<String, String>> load() async => Map<String, String>.of(values);

  @override
  Future<void> save(Map<String, String> rejections) async {
    values = Map<String, String>.of(rejections);
  }
}
