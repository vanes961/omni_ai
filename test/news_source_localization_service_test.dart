import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:omni_ai/features/news/models/news_article.dart';
import 'package:omni_ai/features/news/services/news_source_localization_service.dart';

void main() {
  const service = NewsSourceLocalizationService();

  test('keeps Russian match and suppresses the matching foreign duplicate', () async {
    final foreign = _article(
      id: 'foreign',
      language: 'en',
      title: 'Nintendo Switch 2 release date revealed',
    );
    final russian = _article(
      id: 'russian',
      language: 'ru',
      title: 'Раскрыта дата выхода Nintendo Switch 2',
    );

    final result = await service.localizeCandidates([foreign, russian]);

    expect(result, hasLength(1));
    expect(result.single, same(russian));
  });

  test('retains foreign articles without a reliable Russian match', () async {
    final foreign = _article(
      id: 'foreign',
      language: 'en',
      title: 'Nintendo announces a new console',
    );
    final russian = _article(
      id: 'russian',
      language: 'ru',
      title: 'Valve reveals a handheld gaming device',
    );

    final result = await service.localizeCandidates([foreign, russian]);

    expect(result, hasLength(2));
    expect(result, contains(foreign));
    expect(result, contains(russian));
  });

  test(
    'translates unmatched foreign articles through the shared AI engine',
    () async {
    final foreign = _article(
      id: 'foreign',
      language: 'en',
      title: 'A new console is announced',
    );
    final service = NewsSourceLocalizationService(
      aiEngine: AIEngine(provider: _TranslationProvider()),
    );

    final result = await service.localizeCandidates([foreign]);

    expect(result, hasLength(1));
    expect(result.single.title, 'Анонсирована новая консоль');
    expect(result.single.summary, 'Описание на русском языке');
    expect(result.single.language, 'ru');
    expect(result.single.sourceUrl, foreign.sourceUrl);
    expect(result.single.id, foreign.id);
  });

  test('does not suppress Russian articles during processing', () async {
    final russian = _article(
      id: 'russian',
      language: 'ru',
      title: 'Локальная новость без иностранного оригинала',
    );

    final result = await service.localizeCandidates([russian]);

    expect(result, hasLength(1));
    expect(result.single, same(russian));
  });
}

NewsArticle _article({
  required String id,
  required String language,
  required String title,
}) {
  return NewsArticle(
    id: id,
    title: title,
    summary: '',
    sourceName: 'Source $id',
    sourceUrl: 'https://example.com/$id',
    publishedAt: DateTime.utc(2026, 10, 10, 12),
    topics: const ['games'],
    language: language,
  );
}


class _TranslationProvider implements AIProvider {
  @override
  String get id => 'test-translation';

  @override
  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  }) async {
    return AIResponse(
      requestId: request.id,
      text:
          '{"title":"Анонсирована новая консоль","summary":"Описание на русском языке"}',
      providerId: id,
      generatedAt: DateTime.utc(2026, 10, 12),
    );
  }
}
