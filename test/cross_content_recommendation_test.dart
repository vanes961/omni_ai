import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/data/cross_content_recommendation.dart';

void main() {
  const engine = CrossContentRecommendationEngine();

  const progress = CrossContentProgress(
    contentId: 'tmdb:tv:100',
    type: CrossContentType.anime,
    episode: 8,
  );

  CrossContentRelation relation({
    String targetId = 'mangadex:123',
    double confidence = 0.95,
    int? requiredEpisode = 8,
    int? safeChapter = 1,
    String sourceUrl = 'https://catalog.example/record/123',
    CrossContentRelationKind kind = CrossContentRelationKind.sourceMaterial,
  }) => CrossContentRelation(
    sourceId: 'tmdb:tv:100',
    targetId: targetId,
    sourceType: CrossContentType.anime,
    targetType: CrossContentType.manga,
    kind: kind,
    sourceName: 'Verified catalog',
    sourceUrl: sourceUrl,
    confidence: confidence,
    requiredSourceEpisode: requiredEpisode,
    safeTargetChapter: safeChapter,
  );

  test('returns verified cross-content links with safe hand-off point', () {
    final results = engine.recommend(
      progress: progress,
      relations: [relation()],
    );

    expect(results, hasLength(1));
    expect(results.single.targetId, 'mangadex:123');
    expect(results.single.safeStartPosition, 1);
    expect(results.single.score, greaterThan(0.95));
  });

  test('does not reveal relation before source progress boundary', () {
    final results = engine.recommend(
      progress: const CrossContentProgress(
        contentId: 'tmdb:tv:100',
        type: CrossContentType.anime,
        episode: 7,
      ),
      relations: [relation(requiredEpisode: 8)],
    );

    expect(results, isEmpty);
  });

  test('rejects low-confidence and unverifiable relations', () {
    final results = engine.recommend(
      progress: progress,
      relations: [
        relation(targetId: 'weak', confidence: 0.4),
        relation(targetId: 'unsafe', sourceUrl: 'javascript:alert(1)'),
      ],
    );

    expect(results, isEmpty);
  });

  test('omits already saved targets and self-links', () {
    final results = engine.recommend(
      progress: progress,
      alreadySavedIds: {'saved'},
      relations: [
        relation(targetId: 'saved'),
        relation(targetId: 'tmdb:tv:100'),
      ],
    );

    expect(results, isEmpty);
  });

  test('ranks adaptation/source material above weaker relation kinds', () {
    final results = engine.recommend(
      progress: progress,
      relations: [
        relation(
          targetId: 'franchise',
          kind: CrossContentRelationKind.sameFranchise,
          confidence: 0.8,
        ),
        relation(
          targetId: 'adaptation',
          kind: CrossContentRelationKind.adaptation,
          confidence: 0.8,
        ),
      ],
    );

    expect(results.map((item) => item.targetId), ['adaptation', 'franchise']);
  });

  test('requires HTTPS evidence and confidence in valid range', () {
    expect(
      relation(sourceUrl: 'http://catalog.example/record').hasValidEvidence,
      isFalse,
    );
    expect(
      CrossContentRelation(
        sourceId: 'a',
        targetId: 'b',
        sourceType: CrossContentType.anime,
        targetType: CrossContentType.manga,
        kind: CrossContentRelationKind.adaptation,
        sourceName: 'catalog',
        sourceUrl: 'https://catalog.example/record',
        confidence: 1.5,
      ).hasValidEvidence,
      isFalse,
    );
  });
}
