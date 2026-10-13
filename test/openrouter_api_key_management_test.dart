import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/di/ai_dependencies.dart';
import 'package:omni_ai/providers/openrouter/openrouter_api_key_source.dart';

void main() {
  group('OpenRouter API key management', () {
    test('saves, reads, and deletes a user-owned key', () async {
      final store = _MemoryKeyStore();
      final dependencies = AIDependencies(apiKeySource: store);
      addTearDown(dependencies.dispose);

      expect(await dependencies.hasCloudApiKey, isFalse);

      await dependencies.saveCloudApiKey('  sk-or-test-key  ');

      expect(store.value, 'sk-or-test-key');
      expect(await dependencies.hasCloudApiKey, isTrue);
      expect(await store.readApiKey(), 'sk-or-test-key');

      await dependencies.deleteCloudApiKey();

      expect(store.value, isNull);
      expect(await dependencies.hasCloudApiKey, isFalse);
    });

    test('rejects an empty key without overwriting the stored key', () async {
      final store = _MemoryKeyStore()..value = 'existing-key';
      final dependencies = AIDependencies(apiKeySource: store);
      addTearDown(dependencies.dispose);

      await expectLater(
        dependencies.saveCloudApiKey('  '),
        throwsArgumentError,
      );

      expect(store.value, 'existing-key');
    });

    test('does not allow mutation when the source is read-only', () async {
      final dependencies = AIDependencies(
        apiKeySource: const _ReadOnlyKeySource(),
      );
      addTearDown(dependencies.dispose);

      await expectLater(
        dependencies.saveCloudApiKey('sk-or-test-key'),
        throwsStateError,
      );
      await expectLater(
        dependencies.deleteCloudApiKey(),
        throwsStateError,
      );
    });
  });
}

class _MemoryKeyStore implements OpenRouterApiKeyStore {
  String? value;

  @override
  Future<String?> readApiKey() async => value;

  @override
  Future<void> writeApiKey(String apiKey) async {
    value = apiKey.trim();
  }

  @override
  Future<void> deleteApiKey() async {
    value = null;
  }
}

class _ReadOnlyKeySource implements OpenRouterApiKeySource {
  const _ReadOnlyKeySource();

  @override
  Future<String?> readApiKey() async => null;
}
