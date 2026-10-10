import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:omni_ai/features/news/models/news_article.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';
import 'package:omni_ai/features/news/services/news_digest_service.dart';

void main() {
  test('does not call AI when no interests are selected', () async {
    final provider = _FakeProvider();
    final service = NewsDigestService(engine: AIEngine(provider: provider));
    final result = await service.createDigest(
      profile: const NewsInterestProfile(),
      articles: [_article('anime')],
    );
    expect(result, isNull);
    expect(provider.requests, isEmpty);
  });

  test('does not summarize articles outside selected topics', () async {
    final provider = _FakeProvider();
    final service = NewsDigestService(engine: AIEngine(provider: provider));
    final result = await service.createDigest(
      profile: const NewsInterestProfile(topics: ['anime']),
      articles: [_article('technology')],
    );
    expect(result, isNull);
    expect(provider.requests, isEmpty);
  });

  test('summarizes only selected topic articles', () async {
    final provider = _FakeProvider();
    final service = NewsDigestService(engine: AIEngine(provider: provider));
    final result = await service.createDigest(
      profile: const NewsInterestProfile(topics: ['anime']),
      requestId: 'digest-test',
      articles: [_article('anime'), _article('technology')],
    );
    expect(result, 'Персональный дайджест');
    expect(provider.requests, hasLength(1));
    expect(provider.requests.single.id, 'digest-test');
    expect(provider.requests.single.prompt, contains('Anime headline'));
    expect(provider.requests.single.prompt, isNot(contains('Technology headline')));
    expect(provider.requests.single.metadata['feature'], 'news_digest');
  });
}

NewsArticle _article(String topic) => NewsArticle(
  id: topic,
  title: topic == 'anime' ? 'Anime headline' : 'Technology headline',
  summary: 'Short source excerpt',
  sourceName: 'Test Source',
  sourceUrl: 'https://example.com/$topic',
  publishedAt: DateTime.utc(2026, 10, 10),
  topics: [topic],
);

class _FakeProvider implements AIProvider {
  final requests = <AIRequest>[];
  @override
  String get id => 'test';
  @override
  Future<AIResponse> complete(AIRequest request, {
    required AICancellationToken cancellationToken,
  }) async {
    requests.add(request);
    return AIResponse(
      requestId: request.id,
      text: 'Персональный дайджест',
      providerId: id,
      generatedAt: DateTime.utc(2026, 10, 10),
    );
  }
}
