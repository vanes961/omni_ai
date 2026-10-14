import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/data/cross_content_recommendation.dart';
import 'package:omni_ai/features/media/services/anilist_relation_service.dart';

void main() {
  group('AniListRelationService', () {
    test('maps catalog relations only when a verified spoiler boundary exists', () {
      final relations = AniListRelationService.parseMangaRelations(
        _payload([
          _edge('ADAPTATION', 101, 'ANIME'),
          _edge('SEQUEL', 202, 'MANGA'),
          _edge('ADAPTATION', 303, 'ANIME'),
        ]),
        mangaDexId: 'manga-uuid',
        verifiedBoundaries: const {
          'anilist:anime:101': VerifiedMangaAnimeBoundary(
            sourceChapter: 12,
            safeTargetEpisode: 1,
          ),
          'anilist:manga:202': VerifiedMangaAnimeBoundary(
            sourceChapter: 20,
          ),
        },
      );

      expect(relations, hasLength(2));
      expect(relations[0].sourceId, 'mangadex:manga-uuid');
      expect(relations[0].targetId, 'anilist:anime:101');
      expect(relations[0].kind, CrossContentRelationKind.adaptation);
      expect(relations[0].requiredSourceChapter, 12);
      expect(relations[0].safeTargetEpisode, 1);
      expect(relations[0].sourceUrl, 'https://mangadex.org/title/manga-uuid');
      expect(relations[1].targetId, 'anilist:manga:202');
      expect(relations[1].kind, CrossContentRelationKind.sequel);
      expect(relations[1].requiredSourceChapter, 20);
    });

    test('rejects unsafe links, unsupported relation kinds and malformed nodes', () {
      final relations = AniListRelationService.parseMangaRelations(
        _payload([
          _edge('ADAPTATION', 1, 'ANIME', url: 'http://anilist.co/anime/1'),
          _edge('CHARACTER', 2, 'ANIME'),
          _edge('ADAPTATION', 3, 'MOVIE'),
          {'relationType': 'ADAPTATION', 'node': null},
          _edge('ADAPTATION', 4, 'ANIME'),
        ]),
        mangaDexId: 'manga-uuid',
        verifiedBoundaries: const {
          'anilist:anime:1': VerifiedMangaAnimeBoundary(sourceChapter: 1),
          'anilist:anime:4': VerifiedMangaAnimeBoundary(sourceChapter: 0),
        },
      );

      expect(relations, isEmpty);
    });

    test('rejects invalid boundaries and malformed top-level payloads', () {
      expect(
        AniListRelationService.parseMangaRelations(
          _payload([_edge('ADAPTATION', 1, 'ANIME')]),
          mangaDexId: 'manga-uuid',
          verifiedBoundaries: const {
            'anilist:anime:1': VerifiedMangaAnimeBoundary(
              sourceChapter: -1,
              safeTargetEpisode: 0,
            ),
          },
        ),
        isEmpty,
      );
      expect(
        AniListRelationService.parseMangaRelations(
          null,
          mangaDexId: 'manga-uuid',
          verifiedBoundaries: const {},
        ),
        isEmpty,
      );
    });

    test('only unlocks relation when saved reading progress reaches boundary', () {
      final relation = AniListRelationService.parseMangaRelations(
        _payload([_edge('ADAPTATION', 101, 'ANIME')]),
        mangaDexId: 'manga-uuid',
        verifiedBoundaries: const {
          'anilist:anime:101': VerifiedMangaAnimeBoundary(
            sourceChapter: 12,
            safeTargetEpisode: 1,
          ),
        },
      ).single;
      const engine = CrossContentRecommendationEngine();

      expect(
        engine.recommend(
          progress: const CrossContentProgress(
            contentId: 'mangadex:manga-uuid',
            type: CrossContentType.manga,
            chapter: 11,
          ),
          relations: [relation],
        ),
        isEmpty,
      );
      expect(
        engine.recommend(
          progress: const CrossContentProgress(
            contentId: 'mangadex:manga-uuid',
            type: CrossContentType.manga,
            chapter: 12,
          ),
          relations: [relation],
        ),
        hasLength(1),
      );
    });
  });
}

Map<String, Object?> _payload(List<Object?> edges) => {
  'data': {
    'Media': {
      'id': 555,
      'relations': {'edges': edges},
    },
  },
};

Map<String, Object?> _edge(
  String relationType,
  int id,
  String type, {
  String? url,
}) => {
  'relationType': relationType,
  'node': {
    'id': id,
    'type': type,
    'siteUrl': url ?? 'https://anilist.co/${type.toLowerCase()}/$id',
  },
};
