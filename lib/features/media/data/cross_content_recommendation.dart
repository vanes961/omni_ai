/// Shared domain primitives for spoiler-aware recommendations across media types.
///
/// Relations are catalog evidence, not AI-generated guesses. A relation may
/// only be shown when its source is verifiable and the viewer has reached the
/// configured source boundary. Target boundaries are hints for safe hand-off,
/// never permission to reveal plot details.
enum CrossContentType { movie, series, anime, manga, trailer }

enum CrossContentRelationKind {
  adaptation,
  sourceMaterial,
  sequel,
  prequel,
  sameFranchise,
  spinOff,
}

class CrossContentProgress {
  const CrossContentProgress({
    required this.contentId,
    required this.type,
    this.episode,
    this.chapter,
  });

  final String contentId;
  final CrossContentType type;
  final int? episode;
  final int? chapter;

  int? get position => type == CrossContentType.manga ? chapter : episode;
}

class CrossContentRelation {
  const CrossContentRelation({
    required this.sourceId,
    required this.targetId,
    required this.sourceType,
    required this.targetType,
    required this.kind,
    required this.sourceName,
    required this.sourceUrl,
    required this.confidence,
    this.requiredSourceEpisode,
    this.requiredSourceChapter,
    this.safeTargetEpisode,
    this.safeTargetChapter,
  });

  final String sourceId;
  final String targetId;
  final CrossContentType sourceType;
  final CrossContentType targetType;
  final CrossContentRelationKind kind;

  /// Human-readable catalog/provider name for the evidence.
  final String sourceName;

  /// HTTPS URL to the catalog record or other verifiable evidence.
  final String sourceUrl;

  /// Confidence from 0 to 1, assigned by the catalog adapter, not the UI.
  final double confidence;

  /// Do not surface this relation until the viewer reaches this source point.
  final int? requiredSourceEpisode;
  final int? requiredSourceChapter;

  /// Safe hand-off point, when the catalog provides a verified boundary.
  final int? safeTargetEpisode;
  final int? safeTargetChapter;

  bool get hasValidEvidence {
    final uri = Uri.tryParse(sourceUrl);
    return sourceName.trim().isNotEmpty &&
        uri != null &&
        uri.scheme.toLowerCase() == 'https' &&
        uri.host.isNotEmpty &&
        confidence >= 0 &&
        confidence <= 1;
  }

  bool isUnlockedBy(CrossContentProgress progress) {
    if (!hasValidEvidence ||
        progress.contentId != sourceId ||
        progress.type != sourceType) {
      return false;
    }
    final requiredPosition = sourceType == CrossContentType.manga
        ? requiredSourceChapter
        : requiredSourceEpisode;
    if (requiredPosition == null) return true;
    final currentPosition = progress.position;
    return currentPosition != null && currentPosition >= requiredPosition;
  }

  int? get safeTargetPosition => targetType == CrossContentType.manga
      ? safeTargetChapter
      : safeTargetEpisode;
}

class CrossContentRecommendation {
  const CrossContentRecommendation({
    required this.relation,
    required this.score,
  });

  final CrossContentRelation relation;
  final double score;

  String get targetId => relation.targetId;

  /// Deliberately contains no plot summary or generated spoiler text.
  int? get safeStartPosition => relation.safeTargetPosition;
}

/// Deterministic, local-only recommendation ranking. The caller supplies
/// verified catalog relations and observed progress; this class does no
/// network calls and never invents anime/manga connections.
class CrossContentRecommendationEngine {
  const CrossContentRecommendationEngine({this.minimumConfidence = 0.7});

  final double minimumConfidence;

  List<CrossContentRecommendation> recommend({
    required CrossContentProgress progress,
    required Iterable<CrossContentRelation> relations,
    Set<String> alreadySavedIds = const <String>{},
  }) {
    final bestByTarget = <String, CrossContentRecommendation>{};
    for (final relation in relations) {
      if (!relation.isUnlockedBy(progress) ||
          relation.confidence < minimumConfidence ||
          relation.targetId.trim().isEmpty ||
          relation.targetId == progress.contentId ||
          alreadySavedIds.contains(relation.targetId)) {
        continue;
      }
      // Confidence is the baseline; relation type adds a small, explainable
      // preference without allowing weak evidence to outrank verified links.
      final kindBonus = switch (relation.kind) {
        CrossContentRelationKind.adaptation ||
        CrossContentRelationKind.sourceMaterial => 0.12,
        CrossContentRelationKind.sequel ||
        CrossContentRelationKind.prequel => 0.08,
        CrossContentRelationKind.sameFranchise => 0.04,
        CrossContentRelationKind.spinOff => 0.02,
      };
      final candidate = CrossContentRecommendation(
        relation: relation,
        score: relation.confidence + kindBonus,
      );
      final previous = bestByTarget[relation.targetId];
      if (previous == null || candidate.score > previous.score) {
        bestByTarget[relation.targetId] = candidate;
      }
    }
    final candidates = bestByTarget.values.toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : a.targetId.compareTo(b.targetId);
      });
    return List<CrossContentRecommendation>.unmodifiable(candidates);
  }
}
