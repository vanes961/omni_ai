import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class InterestFeedbackStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Stores locally the topics a user explicitly asks to see less often.
class InterestFeedbackRepository {
  InterestFeedbackRepository({InterestFeedbackStore? store})
    : _store = store ?? _SharedPreferencesInterestFeedbackStore();

  static const storageKey = 'omni_ai.interest_feedback.less.v1';
  final InterestFeedbackStore _store;

  Future<Set<String>> loadLessInterested() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.trim().isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded
          .whereType<String>()
          .map(_normalize)
          .where((topic) => topic.isNotEmpty)
          .toSet();
    } on FormatException {
      return <String>{};
    }
  }

  Future<Set<String>> addLessInterested(Iterable<String> topics) async {
    final current = await loadLessInterested();
    current.addAll(topics.map(_normalize).where((topic) => topic.isNotEmpty));
    await _store.write(storageKey, jsonEncode(current.toList()..sort()));
    return Set<String>.unmodifiable(current);
  }

  Future<Set<String>> removeLessInterested(Iterable<String> topics) async {
    final current = await loadLessInterested();
    current.removeAll(topics.map(_normalize));
    await _store.write(storageKey, jsonEncode(current.toList()..sort()));
    return Set<String>.unmodifiable(current);
  }

  String _normalize(String value) => value.trim().toLowerCase();
}

class _SharedPreferencesInterestFeedbackStore implements InterestFeedbackStore {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);
}
