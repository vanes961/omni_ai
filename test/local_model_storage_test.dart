import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/core/ai_engine/local/local_model_storage.dart';

void main() {
  late Directory temporaryDirectory;
  late LocalModelStorage storage;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'omni-model-test-',
    );
  });

  tearDown(() async {
    storage.dispose();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  LocalModelSpec spec({int expectedBytes = 10}) {
    return LocalModelSpec(
      id: 'test-model',
      displayName: 'Test model',
      fileName: 'test.gguf',
      downloadUri: 'https://example.test/test.gguf',
      expectedBytesApprox: expectedBytes,
    );
  }

  test('downloads and atomically installs a complete model', () async {
    final bytes = Uint8List.fromList(List<int>.generate(10, (i) => i));
    storage = LocalModelStorage(
      client: MockClient((_) async => http.Response.bytes(bytes, 200)),
      supportDirectoryProvider: () async => temporaryDirectory,
    );
    var lastProgress = 0;

    final file = await storage.download(
      spec(),
      onProgress: (received, total) => lastProgress = received,
    );

    expect(await file.readAsBytes(), bytes);
    expect(lastProgress, 10);
    expect(await storage.isDownloaded(spec()), isTrue);
    expect(await File('${file.path}.part').exists(), isFalse);
  });

  test('removes a partial file when response size does not match', () async {
    storage = LocalModelStorage(
      client: MockClient(
        (_) async =>
            http.Response('123', 200, headers: {'content-length': '10'}),
      ),
      supportDirectoryProvider: () async => temporaryDirectory,
    );

    await expectLater(
      storage.download(spec()),
      throwsA(isA<FormatException>()),
    );

    final file = await storage.modelFile(spec());
    expect(await File('${file.path}.part').exists(), isFalse);
    expect(await file.exists(), isFalse);
  });

  test('removes a partial file when the server returns an error', () async {
    storage = LocalModelStorage(
      client: MockClient((_) async => http.Response('not found', 404)),
      supportDirectoryProvider: () async => temporaryDirectory,
    );

    await expectLater(storage.download(spec()), throwsA(isA<HttpException>()));

    final file = await storage.modelFile(spec());
    expect(await File('${file.path}.part').exists(), isFalse);
  });

  test('removes a partial file when the progress callback throws', () async {
    storage = LocalModelStorage(
      client: MockClient(
        (_) async => http.Response.bytes(
          Uint8List.fromList(List<int>.filled(10, 1)),
          200,
        ),
      ),
      supportDirectoryProvider: () async => temporaryDirectory,
    );

    await expectLater(
      storage.download(
        spec(),
        onProgress: (_, _) => throw StateError('cancel'),
      ),
      throwsA(isA<StateError>()),
    );

    final file = await storage.modelFile(spec());
    expect(await File('${file.path}.part').exists(), isFalse);
  });

  test(
    'delete removes both the installed model and stale partial file',
    () async {
      storage = LocalModelStorage(
        client: MockClient((_) async => http.Response('', 200)),
        supportDirectoryProvider: () async => temporaryDirectory,
      );
      final file = await storage.modelFile(spec());
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List<int>.filled(10, 1));
      await File('${file.path}.part').writeAsBytes([1]);

      await storage.delete(spec());

      expect(await file.exists(), isFalse);
      expect(await File('${file.path}.part').exists(), isFalse);
    },
  );
}
