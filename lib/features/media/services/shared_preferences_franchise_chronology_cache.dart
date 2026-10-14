import 'dart:convert';

import 'package:omni_ai/features/media/services/franchise_chronology_coordinator.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local persistence for verified chronology results.
///
/// Entries expire after [maxAge]; callers fall back to release order whenever
/// the saved payload is missing, stale, or malformed.
class SharedPreferencesFranchiseChronologyCache
    implements FranchiseChronologyCache {
  const SharedPreferencesFranchiseChronologyCache({
    this.maxAge = const Duration(days: 30),
  });

  static const _keyPrefix = 'omni_ai.franchise_chronology.v1.';
  final Duration maxAge;

  String _key(String franchiseId) =>
      '$_keyPrefix${Uri.encodeComponent(franchiseId)}';

  @override
  Future<List<MediaFranchiseEntry>?> read(String franchiseId) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key(franchiseId));
    if (raw == null) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != 1 ||
          decoded['savedAt'] is! int ||
          decoded['entries'] is! List) {
        return null;
      }

      final savedAt = DateTime.fromMillisecondsSinceEpoch(
        decoded['savedAt'] as int,
        isUtc: true,
      );
      final age = DateTime.now().toUtc().difference(savedAt);
      if (age.isNegative || age > maxAge) return null;

      final entries = <MediaFranchiseEntry>[];
      for (final value in decoded['entries'] as List) {
        if (value is! Map<String, dynamic>) return null;
        final id = value['id'];
        final title = value['title'];
        final overview = value['overview'];
        final releaseDate = value['releaseDate'];
        final posterUrl = value['posterUrl'];
        final order = value['chronologyOrder'];
        final spoilerRisk = value['chronologySpoilerRisk'];
        final sourceUrl = value['chronologySourceUrl'];
        if (id is! String ||
            title is! String ||
            overview is! String ||
            releaseDate is! String ||
            posterUrl is! String ||
            order is! int ||
            spoilerRisk is! bool ||
            sourceUrl is! String) {
          return null;
        }
        entries.add(
          MediaFranchiseEntry(
            id: id,
            title: title,
            overview: overview,
            releaseDate: releaseDate,
            posterUrl: posterUrl,
            chronologyOrder: order,
            chronologySpoilerRisk: spoilerRisk,
            chronologySourceUrl: sourceUrl,
          ),
        );
      }
      return List<MediaFranchiseEntry>.unmodifiable(entries);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(
    String franchiseId,
    List<MediaFranchiseEntry> entries,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final payload = <String, Object?>{
      'version': 1,
      'savedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      'entries': entries
          .map(
            (entry) => <String, Object?>{
              'id': entry.id,
              'title': entry.title,
              'overview': entry.overview,
              'releaseDate': entry.releaseDate,
              'posterUrl': entry.posterUrl,
              'chronologyOrder': entry.chronologyOrder,
              'chronologySpoilerRisk': entry.chronologySpoilerRisk,
              'chronologySourceUrl': entry.chronologySourceUrl,
            },
          )
          .toList(growable: false),
    };
    await preferences.setString(_key(franchiseId), jsonEncode(payload));
  }
}
