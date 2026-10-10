import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/news/data/shared_preferences_news_interest_repository.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';

void main() {
  test('persists and restores user-selected interests', () async {
    final store = _Store();
    final repository = SharedPreferencesNewsInterestRepository(store: store);
    const profile = NewsInterestProfile(
      topics: ['anime', 'technology'],
      languages: ['ru'],
      regions: ['nl'],
    );

    await repository.save(profile);
    final restored = await SharedPreferencesNewsInterestRepository(
      store: store,
    ).load();

    expect(restored.topics, containsAll(profile.topics));
    expect(restored.languages, ['ru']);
    expect(restored.regions, ['nl']);
    expect(
      jsonDecode(store.values[SharedPreferencesNewsInterestRepository.storageKey]!)
          ['topics'],
      contains('anime'),
    );
    await repository.dispose();
  });

  test('corrupt settings safely reset to no selected topics', () async {
    final store = _Store()
      ..values[SharedPreferencesNewsInterestRepository.storageKey] = 'broken';
    final repository = SharedPreferencesNewsInterestRepository(store: store);

    expect((await repository.load()).topics, isEmpty);
    expect(store.values, isEmpty);
    await repository.dispose();
  });
}

class _Store implements NewsProfileStringStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
