import 'dart:convert';

import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:omni_ai/features/media/services/franchise_chronology_coordinator.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';

/// Proposes franchise chronology using OpenRouter's bounded web-search tool.
/// Model-written URLs are discarded unless they exactly match a URL citation
/// returned by the provider for this same response.
class OpenRouterFranchiseChronologyResearcher {
  const OpenRouterFranchiseChronologyResearcher({
    required this.engine,
    this.localEngine,
  });

  final AIEngine engine;
  final AIEngine? localEngine;

  Future<List<FranchiseChronologyProposal>> research({
    required String franchiseId,
    required List<MediaFranchiseEntry> entries,
  }) async {
    if (entries.isEmpty) return const [];

    final payload = entries
        .map(
          (entry) => <String, Object?>{
            'id': entry.id,
            'title': entry.title,
            'releaseDate': entry.releaseDate,
            'overview': entry.overview.length > 360
                ? entry.overview.substring(0, 360)
                : entry.overview,
          },
        )
        .toList(growable: false);
    final response = await engine.execute(
      AIRequest(
        id:
            'franchise-chronology-${Uri.encodeComponent(franchiseId)}-'
            '${DateTime.now().millisecondsSinceEpoch}',
        systemInstruction:
            'Ты исследователь хронологии кинофраншиз. Используй веб-поиск, '
            'не выдумывай источники и не подменяй порядок выхода порядком '
            'просмотра. Если надёжно установить полный порядок нельзя, '
            'верни пустой JSON-массив. Ответ — только валидный JSON-массив.',
        prompt:
            '''
Определи рекомендуемый сюжетный порядок просмотра только для перечисленных
элементов одной франшизы. Используй веб-поиск. У каждого элемента должен
быть источник, подтверждающий его участие во франшизе или его место в
хронологии. В sourceUrl указывай точный URL из результатов поиска, который
будет возвращён провайдером как URL citation; не придумывай адреса.

Верни только JSON-массив объектов строго такой формы:
[{"itemId":"исходный ID","order":1,"sourceUrl":"https://...","spoilerRisk":false}]

Правила:
- включи каждый исходный ID ровно один раз; не добавляй новые элементы;
- order — уникальный целочисленный порядок от 1 до N;
- spoilerRisk=true, если этот порядок может раскрыть важный сюжетный поворот;
- если нельзя найти подходящий источник для каждого элемента, верни [];
- не включай markdown, пояснения или текст вне JSON.

Франшиза: $franchiseId
Элементы:
${jsonEncode(payload)}
''',
        metadata: const {
          'enableWebSearch': true,
          'purpose': 'franchise_chronology',
        },
      ),
    );

    final citations = _readCitations(response.metadata['webSearchCitations']);
    if (citations.isEmpty) return const [];
    final decoded = _decodeJson(response.text);
    if (decoded is! List) return const [];

    final proposals = <FranchiseChronologyProposal>[];
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final itemId = raw['itemId'];
      final order = raw['order'];
      final sourceUrl = raw['sourceUrl'];
      final spoilerRisk = raw['spoilerRisk'];
      if (itemId is! String ||
          order is! int ||
          sourceUrl is! String ||
          spoilerRisk is! bool) {
        continue;
      }
      final citation = citations[sourceUrl];
      if (citation == null) continue;
      proposals.add(
        FranchiseChronologyProposal(
          itemId: itemId,
          order: order,
          sourceUrl: sourceUrl,
          spoilerRisk: spoilerRisk,
          sourceTitle: citation.title,
          sourceExcerpt: citation.excerpt,
        ),
      );
    }
    final cloudProposals = List<FranchiseChronologyProposal>.unmodifiable(
      proposals,
    );
    final local = localEngine;
    if (local == null || cloudProposals.length != entries.length) {
      return cloudProposals;
    }
    return _orderLocally(
      engine: local,
      franchiseId: franchiseId,
      entries: entries,
      proposals: cloudProposals,
    );
  }

  Future<List<FranchiseChronologyProposal>> _orderLocally({
    required AIEngine engine,
    required String franchiseId,
    required List<MediaFranchiseEntry> entries,
    required List<FranchiseChronologyProposal> proposals,
  }) async {
    final byId = {for (final proposal in proposals) proposal.itemId: proposal};
    if (byId.length != entries.length ||
        entries.any((entry) => !byId.containsKey(entry.id))) {
      return proposals;
    }
    final evidence = entries
        .map((entry) {
          final proposal = byId[entry.id]!;
          return <String, Object?>{
            'id': entry.id,
            'title': entry.title,
            'releaseDate': entry.releaseDate,
            'overview': entry.overview,
            'sourceUrl': proposal.sourceUrl,
            'sourceTitle': proposal.sourceTitle,
            'sourceExcerpt': proposal.sourceExcerpt,
            'cloudSuggestedOrder': proposal.order,
            'cloudSpoilerRisk': proposal.spoilerRisk,
          };
        })
        .toList(growable: false);

    try {
      final response = await engine.execute(
        AIRequest(
          id:
              'franchise-local-order-${Uri.encodeComponent(franchiseId)}-'
              '${DateTime.now().millisecondsSinceEpoch}',
          systemInstruction:
              'Ты локальный помощник по хронологии кинофраншиз. Используй '
              'только переданные названия, даты и найденные источники. '
              'Не выдумывай элементы или факты. Если данные неоднозначны, '
              'сохрани предложенный облаком порядок и отметь риск спойлеров.',
          prompt:
              '''
Определи умный сюжетный порядок просмотра для всех элементов ниже.
Облачный AI уже выполнил поиск. Источники и выдержки — реальные URL citations,
полученные от провайдера. Используй их вместе с датами и описаниями; не
создавай новые ссылки. При сомнении сохраняй cloudSuggestedOrder.

Верни только JSON-массив:
[{"itemId":"исходный ID","order":1,"spoilerRisk":false}]
Каждый исходный ID должен встретиться ровно один раз, order должен быть
уникальным целым числом от 1 до N. spoilerRisk отмечает риск раскрытия сюжета.
Не добавляй markdown или пояснения.

Франшиза: $franchiseId
Данные:
${jsonEncode(evidence)}
''',
          metadata: const {'purpose': 'franchise_chronology_local_order'},
        ),
      );
      final decoded = _decodeJson(response.text);
      if (decoded is! List || decoded.length != entries.length) {
        return proposals;
      }
      final orders = <int>{};
      final reordered = <String, Map>{};
      for (final raw in decoded) {
        if (raw is! Map ||
            raw['itemId'] is! String ||
            raw['order'] is! int ||
            raw['spoilerRisk'] is! bool ||
            (raw['order'] as int) < 1 ||
            !orders.add(raw['order'] as int) ||
            reordered.containsKey(raw['itemId'] as String)) {
          return proposals;
        }
        reordered[raw['itemId'] as String] = raw;
      }
      if (reordered.length != entries.length ||
          entries.any((entry) => !reordered.containsKey(entry.id))) {
        return proposals;
      }
      return List<FranchiseChronologyProposal>.unmodifiable(
        entries.map((entry) {
          final ordered = reordered[entry.id]!;
          final source = byId[entry.id]!;
          return FranchiseChronologyProposal(
            itemId: source.itemId,
            order: ordered['order'] as int,
            sourceUrl: source.sourceUrl,
            spoilerRisk: ordered['spoilerRisk'] as bool,
            sourceTitle: source.sourceTitle,
            sourceExcerpt: source.sourceExcerpt,
          );
        }),
      );
    } on Object {
      // If the local model is not ready, keep the cloud's cited proposal.
      return proposals;
    }
  }

  /// Checks that the URL is provider-cited and the citation mentions the
  /// catalog title. This is provenance/relevance checking, not a guarantee
  /// that a source's chronology claim is infallible; incomplete or inconsistent
  /// results are rejected by the coordinator and fall back to release order.
  Future<bool> verifyEvidence({
    required FranchiseChronologyProposal proposal,
    required MediaFranchiseEntry entry,
  }) async {
    final uri = Uri.tryParse(proposal.sourceUrl);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        proposal.sourceTitle?.trim().isNotEmpty != true) {
      return false;
    }
    final evidence = '${proposal.sourceTitle} ${proposal.sourceExcerpt ?? ''}';
    final normalizedEvidence = _normalize(evidence);
    final normalizedTitle = _normalize(entry.title);
    if (normalizedTitle.isEmpty) return false;
    if (normalizedEvidence.contains(normalizedTitle)) return true;

    final tokens = normalizedTitle
        .split(' ')
        .where((token) => token.length >= 3)
        .toSet();
    if (tokens.isEmpty) return false;
    final matches = tokens.where(normalizedEvidence.contains).length;
    return matches >= (tokens.length == 1 ? 1 : 2);
  }

  Map<String, _Citation> _readCitations(Object? value) {
    if (value is! List) return const {};
    final result = <String, _Citation>{};
    for (final raw in value) {
      if (raw is! Map) continue;
      final url = raw['url'];
      final title = raw['title'];
      final excerpt = raw['content'];
      if (url is! String || title is! String) continue;
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme.toLowerCase() != 'https' ||
          uri.host.isEmpty) {
        continue;
      }
      result[url] = _Citation(
        title: title,
        excerpt: excerpt is String ? excerpt : '',
      );
    }
    return result;
  }

  Object? _decodeJson(String value) {
    try {
      return jsonDecode(value.trim());
    } on FormatException {
      return null;
    }
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

class _Citation {
  const _Citation({required this.title, required this.excerpt});

  final String title;
  final String excerpt;
}
