import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/services/franchise_chronology_coordinator.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';

void main() {
  final entries = [
    const MediaFranchiseEntry(
      id: 'tmdb:movie:1',
      title: 'Film One',
      overview: '',
      releaseDate: '2020-01-01',
      posterUrl: '',
    ),
    const MediaFranchiseEntry(
      id: 'tmdb:movie:2',
      title: 'Film Two',
      overview: '',
      releaseDate: '2021-01-01',
      posterUrl: '',
    ),
  ];

  test('accepts a complete chronology only after verifying every source',
      () async {
    final cache = _MemoryChronologyCache();
    var verificationCount = 0;
    final coordinator = FranchiseChronologyCoordinator(
      cache: cache,
      research: ({required franchiseId, required entries}) async => [
        const FranchiseChronologyProposal(
          itemId: 'tmdb:movie:1',
          order: 1,
          sourceUrl: 'https://example.org/film-one',
        ),
        const FranchiseChronologyProposal(
          itemId: 'tmdb:movie:2',
          order: 2,
          sourceUrl: 'https://example.org/film-two',
          spoilerRisk: true,
        ),
      ],
      verifyEvidence: ({required proposal, required entry}) async {
        verificationCount++;
        return proposal.itemId == entry.id;
      },
    );

    final result = await coordinator.resolve(
      franchiseId: 'franchise:example',
      entries: entries,
    );

    expect(verificationCount, 2);
    expect(result.map((entry) => entry.chronologyOrder), [1, 2]);
    expect(result.last.chronologySpoilerRisk, isTrue);
    expect(result.first.chronologySourceUrl, 'https://example.org/film-one');
    expect(cache.values, contains('franchise:example'));
  });

  test('rejects chronology if even one source cannot be verified', () async {
    final coordinator = FranchiseChronologyCoordinator(
      cache: _MemoryChronologyCache(),
      research: ({required franchiseId, required entries}) async => [
        const FranchiseChronologyProposal(
          itemId: 'tmdb:movie:1',
          order: 1,
          sourceUrl: 'https://example.org/film-one',
        ),
        const FranchiseChronologyProposal(
          itemId: 'tmdb:movie:2',
          order: 2,
          sourceUrl: 'https://example.org/film-two',
        ),
      ],
      verifyEvidence: ({required proposal, required entry}) async =>
          proposal.itemId == 'tmdb:movie:1',
    );

    final result = await coordinator.resolve(
      franchiseId: 'franchise:example',
      entries: entries,
    );

    expect(result.every((entry) => entry.chronologyOrder == null), isTrue);
  });

  test('falls back to release metadata when cloud research fails',
      () async {
    final coordinator = FranchiseChronologyCoordinator(
      cache: _MemoryChronologyCache(),
      research: ({required franchiseId, required entries}) async {
        throw Exception('Cloud provider unavailable');
      },
      verifyEvidence: ({required proposal, required entry}) async => false,
    );

    final result = await coordinator.resolve(
      franchiseId: 'franchise:example',
      entries: entries,
    );

    expect(result.map((entry) => entry.id), entries.map((entry) => entry.id));
    expect(result.every((entry) => entry.chronologyOrder == null), isTrue);
  });

  test('rejects duplicate chronology positions and non-HTTPS sources',
      () async {
    final cache = _MemoryChronologyCache();
    final coordinator = FranchiseChronologyCoordinator(
      cache: cache,
      research: ({required franchiseId, required entries}) async => [
        const FranchiseChronologyProposal(
          itemId: 'tmdb:movie:1',
          order: 1,
          sourceUrl: 'https://example.org/film-one',
        ),
        const FranchiseChronologyProposal(
          itemId: 'tmdb:movie:2',
          order: 1,
          sourceUrl: 'http://example.org/film-two',
        ),
      ],
      verifyEvidence: ({required proposal, required entry}) async => true,
    );

    final result = await coordinator.resolve(
      franchiseId: 'franchise:example',
      entries: entries,
    );

    expect(result.every((entry) => entry.chronologyOrder == null), isTrue);
    expect(cache.values, isEmpty);
  });

  test('invalidates cached chronology when franchise membership changes', () async {
    final cache = _MemoryChronologyCache()
      ..stored['franchise:example'] = [
        const MediaFranchiseEntry(
          id: 'tmdb:movie:1',
          title: 'Film One',
          overview: '',
          releaseDate: '',
          posterUrl: '',
          chronologyOrder: 2,
          chronologySourceUrl: 'https://example.org/film-one',
        ),
        const MediaFranchiseEntry(
          id: 'tmdb:movie:2',
          title: 'Film Two',
          overview: '',
          releaseDate: '',
          posterUrl: '',
          chronologyOrder: 1,
          chronologySourceUrl: 'https://example.org/film-two',
        ),
      ];
    var researched = false;
    final updatedEntries = [
      ...entries,
      const MediaFranchiseEntry(
        id: 'tmdb:movie:3',
        title: 'Newly added film',
        overview: '',
        releaseDate: '2022-01-01',
        posterUrl: '',
      ),
    ];
    final coordinator = FranchiseChronologyCoordinator(
      cache: cache,
      research: ({required franchiseId, required entries}) async {
        researched = true;
        return const [];
      },
      verifyEvidence: ({required proposal, required entry}) async => false,
    );

    final result = await coordinator.resolve(
      franchiseId: 'franchise:example',
      entries: updatedEntries,
    );

    expect(researched, isTrue);
    expect(result.length, 3);
    expect(result.every((entry) => entry.chronologyOrder == null), isTrue);
  });

  test('invalidates cache when a franchise entry was removed', () async {
    final cache = _MemoryChronologyCache()
      ..stored['franchise:example'] = [
        const MediaFranchiseEntry(
          id: 'tmdb:movie:1',
          title: 'Film One',
          overview: '',
          releaseDate: '',
          posterUrl: '',
          chronologyOrder: 1,
          chronologySourceUrl: 'https://example.org/film-one',
        ),
        const MediaFranchiseEntry(
          id: 'tmdb:movie:2',
          title: 'Film Two',
          overview: '',
          releaseDate: '',
          posterUrl: '',
          chronologyOrder: 2,
          chronologySourceUrl: 'https://example.org/film-two',
        ),
      ];
    var researched = false;
    final coordinator = FranchiseChronologyCoordinator(
      cache: cache,
      research: ({required franchiseId, required entries}) async {
        researched = true;
        return const [];
      },
      verifyEvidence: ({required proposal, required entry}) async => false,
    );

    final result = await coordinator.resolve(
      franchiseId: 'franchise:example',
      entries: [entries.first],
    );

    expect(researched, isTrue);
    expect(result, hasLength(1));
    expect(result.single.chronologyOrder, isNull);
  });

  test('rejects chronology positions outside the contiguous 1..N range',
      () async {
    final coordinator = FranchiseChronologyCoordinator(
      cache: _MemoryChronologyCache(),
      research: ({required franchiseId, required entries}) async => [
        const FranchiseChronologyProposal(
          itemId: 'tmdb:movie:1',
          order: 1,
          sourceUrl: 'https://example.org/film-one',
        ),
        const FranchiseChronologyProposal(
          itemId: 'tmdb:movie:2',
          order: 3,
          sourceUrl: 'https://example.org/film-two',
        ),
      ],
      verifyEvidence: ({required proposal, required entry}) async => true,
    );

    final result = await coordinator.resolve(
      franchiseId: 'franchise:example',
      entries: entries,
    );

    expect(result.every((entry) => entry.chronologyOrder == null), isTrue);
  });

  test('rejects cached chronology positions outside the contiguous 1..N range',
      () async {
    final cache = _MemoryChronologyCache()
      ..stored['franchise:example'] = [
        const MediaFranchiseEntry(
          id: 'tmdb:movie:1',
          title: 'Film One',
          overview: '',
          releaseDate: '',
          posterUrl: '',
          chronologyOrder: 0,
          chronologySourceUrl: 'https://example.org/film-one',
        ),
        const MediaFranchiseEntry(
          id: 'tmdb:movie:2',
          title: 'Film Two',
          overview: '',
          releaseDate: '',
          posterUrl: '',
          chronologyOrder: 2,
          chronologySourceUrl: 'https://example.org/film-two',
        ),
      ];
    var researched = false;
    final coordinator = FranchiseChronologyCoordinator(
      cache: cache,
      research: ({required franchiseId, required entries}) async {
        researched = true;
        return const [];
      },
      verifyEvidence: ({required proposal, required entry}) async => false,
    );

    final result = await coordinator.resolve(
      franchiseId: 'franchise:example',
      entries: entries,
    );

    expect(researched, isTrue);
    expect(result.every((entry) => entry.chronologyOrder == null), isTrue);
  });

  test('uses cached verified chronology without calling cloud research',
      () async {
    final cache = _MemoryChronologyCache()
      ..stored['franchise:example'] = [
        const MediaFranchiseEntry(
          id: 'tmdb:movie:1',
          title: 'Old title',
          overview: '',
          releaseDate: '',
          posterUrl: '',
          chronologyOrder: 2,
          chronologySourceUrl: 'https://example.org/film-one',
        ),
        const MediaFranchiseEntry(
          id: 'tmdb:movie:2',
          title: 'Old title two',
          overview: '',
          releaseDate: '',
          posterUrl: '',
          chronologyOrder: 1,
          chronologySourceUrl: 'https://example.org/film-two',
        ),
      ];
    var researched = false;
    final coordinator = FranchiseChronologyCoordinator(
      cache: cache,
      research: ({required franchiseId, required entries}) async {
        researched = true;
        return const [];
      },
      verifyEvidence: ({required proposal, required entry}) async => false,
    );

    final result = await coordinator.resolve(
      franchiseId: 'franchise:example',
      entries: entries,
    );

    expect(researched, isFalse);
    expect(result.first.title, 'Film One');
    expect(result.first.chronologyOrder, 2);
    expect(result.last.chronologyOrder, 1);
  });
}

class _MemoryChronologyCache implements FranchiseChronologyCache {
  final Map<String, List<MediaFranchiseEntry>> stored = {};

  Iterable<String> get values => stored.keys;

  @override
  Future<List<MediaFranchiseEntry>?> read(String franchiseId) async =>
      stored[franchiseId];

  @override
  Future<void> write(
    String franchiseId,
    List<MediaFranchiseEntry> entries,
  ) async {
    stored[franchiseId] = entries;
  }
}
