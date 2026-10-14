import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/media/services/openrouter_franchise_chronology_researcher.dart';

void main() {
  const entry = MediaFranchiseEntry(
    id: 'tmdb:movie:1',
    title: 'Film One',
    overview: 'A story.',
    releaseDate: '2020-01-01',
    posterUrl: '',
  );
  const url = 'https://example.org/film-one';

  test('accepts only provider-cited URLs and carries citation evidence', () async {
    final researcher = OpenRouterFranchiseChronologyResearcher(
      engine: AIEngine(
        provider: _FakeProvider(
          text: jsonEncode([
            {
              'itemId': entry.id,
              'order': 1,
              'sourceUrl': url,
              'spoilerRisk': false,
            },
          ]),
          citations: const [
            {
              'url': url,
              'title': 'Film One official chronology',
              'content': 'The Film One story is the first chapter.',
            },
          ],
        ),
      ),
    );

    final proposals = await researcher.research(
      franchiseId: 'franchise:film-one',
      entries: const [entry],
    );

    expect(proposals, hasLength(1));
    expect(proposals.single.sourceTitle, 'Film One official chronology');
    expect(proposals.single.sourceExcerpt, contains('first chapter'));
    expect(
      await researcher.verifyEvidence(
        proposal: proposals.single,
        entry: entry,
      ),
      isTrue,
    );
  });

  test('drops model-invented URLs not present in provider citations', () async {
    final researcher = OpenRouterFranchiseChronologyResearcher(
      engine: AIEngine(
        provider: _FakeProvider(
          text: jsonEncode([
            {
              'itemId': entry.id,
              'order': 1,
              'sourceUrl': 'https://invented.example/film-one',
              'spoilerRisk': false,
            },
          ]),
          citations: const [
            {
              'url': url,
              'title': 'Film One official chronology',
              'content': 'The Film One story is the first chapter.',
            },
          ],
        ),
      ),
    );

    final proposals = await researcher.research(
      franchiseId: 'franchise:film-one',
      entries: const [entry],
    );
    expect(proposals, isEmpty);
  });

  test('rejects malformed JSON and unrelated source titles', () async {
    final malformed = OpenRouterFranchiseChronologyResearcher(
      engine: AIEngine(
        provider: _FakeProvider(
          text: 'not JSON',
          citations: const [
            {'url': url, 'title': 'Unrelated source', 'content': 'Other topic.'},
          ],
        ),
      ),
    );
    expect(
      await malformed.research(
        franchiseId: 'franchise:film-one',
        entries: const [entry],
      ),
      isEmpty,
    );

    const unrelated = FranchiseChronologyProposal(
      itemId: 'tmdb:movie:1',
      order: 1,
      sourceUrl: url,
      sourceTitle: 'Unrelated source',
      sourceExcerpt: 'Other topic.',
    );
    expect(
      await malformed.verifyEvidence(proposal: unrelated, entry: entry),
      isFalse,
    );
  });
}

class _FakeProvider implements AIProvider {
  _FakeProvider({required this.text, required this.citations});

  final String text;
  final List<Map<String, Object?>> citations;

  @override
  String get id => 'openrouter';

  @override
  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  }) async {
    expect(request.metadata['enableWebSearch'], isTrue);
    return AIResponse(
      requestId: request.id,
      text: text,
      providerId: id,
      generatedAt: DateTime.utc(2026, 10, 14),
      metadata: {'webSearchCitations': citations},
    );
  }
}
