import 'package:omni_ai/features/media/services/media_search_service.dart';

/// Structured chronology candidate returned by a cloud research adapter.
/// Its claims are not trusted until [FranchiseChronologyEvidenceVerifier]
/// confirms the cited source independently.
class FranchiseChronologyProposal {
  const FranchiseChronologyProposal({
    required this.itemId,
    required this.order,
    required this.sourceUrl,
    this.spoilerRisk = false,
  });

  final String itemId;
  final int order;
  final String sourceUrl;
  final bool spoilerRisk;
}

typedef FranchiseChronologyResearcher =
    Future<List<FranchiseChronologyProposal>> Function({
      required String franchiseId,
      required List<MediaFranchiseEntry> entries,
    });

typedef FranchiseChronologyEvidenceVerifier =
    Future<bool> Function({
      required FranchiseChronologyProposal proposal,
      required MediaFranchiseEntry entry,
    });

/// Persistence boundary for already verified chronology metadata.
abstract interface class FranchiseChronologyCache {
  Future<List<MediaFranchiseEntry>?> read(String franchiseId);

  Future<void> write(
    String franchiseId,
    List<MediaFranchiseEntry> entries,
  );
}

/// Coordinates cache -> cloud research -> independent evidence verification.
///
/// The cloud model can suggest chronology, but cannot certify its own answer.
/// A complete, uniquely ordered set of entries and verified HTTPS evidence are
/// required before chronology metadata is attached to catalog entries.
class FranchiseChronologyCoordinator {
  const FranchiseChronologyCoordinator({
    required this.cache,
    required this.research,
    required this.verifyEvidence,
  });

  final FranchiseChronologyCache cache;
  final FranchiseChronologyResearcher research;
  final FranchiseChronologyEvidenceVerifier verifyEvidence;

  Future<List<MediaFranchiseEntry>> resolve({
    required String franchiseId,
    required List<MediaFranchiseEntry> entries,
    bool forceRefresh = false,
  }) async {
    if (franchiseId.trim().isEmpty || entries.isEmpty) {
      return List<MediaFranchiseEntry>.unmodifiable(entries);
    }

    if (!forceRefresh) {
      final cached = await cache.read(franchiseId);
      final cachedResult = _mergeVerifiedCache(entries, cached);
      if (cachedResult != null) return cachedResult;
    }

    final proposals = await research(
      franchiseId: franchiseId,
      entries: List<MediaFranchiseEntry>.unmodifiable(entries),
    );
    final verified = await _verifyCompleteSet(entries, proposals);
    if (verified == null) {
      return List<MediaFranchiseEntry>.unmodifiable(entries);
    }

    final result = entries.map((entry) {
      final proposal = verified[entry.id]!;
      return MediaFranchiseEntry(
        id: entry.id,
        title: entry.title,
        overview: entry.overview,
        releaseDate: entry.releaseDate,
        posterUrl: entry.posterUrl,
        chronologyOrder: proposal.order,
        chronologySpoilerRisk: proposal.spoilerRisk,
        chronologySourceUrl: proposal.sourceUrl,
      );
    }).toList(growable: false);

    await cache.write(
      franchiseId,
      List<MediaFranchiseEntry>.unmodifiable(result),
    );
    return List<MediaFranchiseEntry>.unmodifiable(result);
  }

  Future<Map<String, FranchiseChronologyProposal>?> _verifyCompleteSet(
    List<MediaFranchiseEntry> entries,
    List<FranchiseChronologyProposal> proposals,
  ) async {
    if (proposals.length != entries.length) return null;

    final entriesById = {for (final entry in entries) entry.id: entry};
    final byId = <String, FranchiseChronologyProposal>{};
    final usedOrders = <int>{};

    for (final proposal in proposals) {
      final entry = entriesById[proposal.itemId];
      final uri = Uri.tryParse(proposal.sourceUrl);
      if (entry == null ||
          byId.containsKey(proposal.itemId) ||
          proposal.order < 0 ||
          !usedOrders.add(proposal.order) ||
          uri == null ||
          uri.scheme.toLowerCase() != 'https' ||
          uri.host.isEmpty) {
        return null;
      }
      final isVerified = await verifyEvidence(
        proposal: proposal,
        entry: entry,
      );
      if (!isVerified) return null;
      byId[proposal.itemId] = proposal;
    }

    return byId.length == entries.length ? byId : null;
  }

  List<MediaFranchiseEntry>? _mergeVerifiedCache(
    List<MediaFranchiseEntry> entries,
    List<MediaFranchiseEntry>? cached,
  ) {
    if (cached == null || cached.length != entries.length) return null;
    final cachedById = {for (final entry in cached) entry.id: entry};
    if (cachedById.length != entries.length) return null;

    final orders = <int>{};
    for (final entry in entries) {
      final saved = cachedById[entry.id];
      final source = Uri.tryParse(saved?.chronologySourceUrl ?? '');
      if (saved?.chronologyOrder == null ||
          !orders.add(saved!.chronologyOrder!) ||
          source == null ||
          source.scheme.toLowerCase() != 'https' ||
          source.host.isEmpty) {
        return null;
      }
    }

    return List<MediaFranchiseEntry>.unmodifiable(
      entries.map((entry) {
        final saved = cachedById[entry.id]!;
        return MediaFranchiseEntry(
          id: entry.id,
          title: entry.title,
          overview: entry.overview,
          releaseDate: entry.releaseDate,
          posterUrl: entry.posterUrl,
          chronologyOrder: saved.chronologyOrder,
          chronologySpoilerRisk: saved.chronologySpoilerRisk,
          chronologySourceUrl: saved.chronologySourceUrl,
        );
      }),
    );
  }
}
