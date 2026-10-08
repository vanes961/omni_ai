import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

void main() {
  group('SharedPreferencesUserPreferencesStore', () {
    test('saves and restores all preference groups after recreation', () async {
      final keyValueStore = _MemoryStringStore();
      final store = SharedPreferencesUserPreferencesStore(store: keyValueStore);
      final preferences = UserPreferences()
        ..categories = ['Аниме', 'Технологии']
        ..favoriteTitles = ['Cyberpunk']
        ..voiceDubbing = ['Anilibria']
        ..tgChannels = ['Игромания'];

      await store.save(preferences);
      final restored = await SharedPreferencesUserPreferencesStore(
        store: keyValueStore,
      ).load();

      expect(restored?.toJson(), preferences.toJson());
      expect(
        jsonDecode(
          keyValueStore.values[SharedPreferencesUserPreferencesStore
              .storageKey]!,
        ),
        preferences.toJson(),
      );
    });

    test(
      'clears a malformed saved profile and reports no completed profile',
      () async {
        final keyValueStore = _MemoryStringStore()
          ..values[SharedPreferencesUserPreferencesStore.storageKey] = '{bad';
        final store = SharedPreferencesUserPreferencesStore(
          store: keyValueStore,
        );

        expect(await store.load(), isNull);
        expect(
          keyValueStore.values.containsKey(
            SharedPreferencesUserPreferencesStore.storageKey,
          ),
          isFalse,
        );
      },
    );
  });
}

class _MemoryStringStore implements UserPreferencesStringStore {
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
