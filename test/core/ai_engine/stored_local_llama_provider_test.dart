import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/local/local_model_storage.dart';
import 'package:omni_ai/core/ai_engine/local/stored_local_llama_provider.dart';
import 'package:omni_ai/core/ai_engine/models/ai_error.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';

void main() {
  test('reports a missing model without attempting a download', () async {
    final directory = await Directory.systemTemp.createTemp('omni-local-ai-');
    final storage = LocalModelStorage(
      supportDirectoryProvider: () async => directory,
    );
    final provider = StoredLocalLlamaProvider(
      storage: storage,
      model: const LocalModelSpec(
        id: 'test-model',
        displayName: 'Test model',
        fileName: 'test.gguf',
        downloadUri: 'https://example.invalid/test.gguf',
        expectedBytesApprox: 10,
      ),
    );

    addTearDown(() async {
      await provider.dispose();
      storage.dispose();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    await expectLater(
      provider.complete(
        AIRequest(id: 'missing-model', prompt: 'Hello'),
        cancellationToken: AICancellationToken(),
      ),
      throwsA(
        isA<AIEngineException>().having(
          (error) => error.error.message,
          'message',
          contains('Local model is not downloaded'),
        ),
      ),
    );

    expect(await directory.list().toList(), isEmpty);
  });
}
