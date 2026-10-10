import 'dart:io';

import 'package:flutter/services.dart';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Metadata for the bundled on-device model.
///
/// The model is bundled into the Android APK by CI and copied into app-private
/// storage on first use. Inference is handled separately.
class LocalModelCatalog {
  const LocalModelCatalog._();

  static const qwen3Small = LocalModelSpec(
    id: 'qwen3-0.6b-q4-k-m',
    displayName: 'Qwen3 0.6B (Q4_K_M)',
    fileName: 'Qwen_Qwen3-0.6B-Q4_K_M.gguf',
    downloadUri:
        'https://huggingface.co/SandLogicTechnologies/Qwen3-GGUF/resolve/main/Qwen_Qwen3-0.6B-Q4_K_M.gguf',
    expectedBytesApprox: 484000000,
    expectedSha256:
        '9acfc1e001311f34b4252001b626f2e466d592a42065f66571bff3790d4e1b14',
  );
}

class LocalModelSpec {
  const LocalModelSpec({
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.downloadUri,
    required this.expectedBytesApprox,
    this.expectedSha256,
  });

  final String id;
  final String displayName;
  final String fileName;
  final String downloadUri;
  final int expectedBytesApprox;
  final String? expectedSha256;
}

/// Stores GGUF files in app-private storage. The production model is copied
/// from the APK; the download method remains available for development tools.
class LocalModelStorage {
  LocalModelStorage({
    http.Client? client,
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _client = client ?? http.Client(),
       _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory;

  static const _channel = MethodChannel('omni_ai/bundled_model');

  final http.Client _client;
  final Future<Directory> Function() _supportDirectoryProvider;

  Future<File> modelFile(LocalModelSpec model) async {
    final directory = await _supportDirectoryProvider();
    return File('${directory.path}/models/${model.fileName}');
  }

  Future<bool> isDownloaded(LocalModelSpec model) async {
    final file = await modelFile(model);
    if (!await file.exists()) return false;
    final length = await file.length();
    return length > 0 && length >= model.expectedBytesApprox * 0.95;
  }

  /// Copies the model packaged inside the APK into app-private storage.
  /// The Android side streams the asset in chunks to avoid loading ~484 MB
  /// into Dart memory at once.
  Future<File> installBundled(LocalModelSpec model) async {
    final destination = await modelFile(model);
    if (await isDownloaded(model)) return destination;

    await destination.parent.create(recursive: true);
    await _channel.invokeMethod<void>('copyBundledModel', <String, Object>{
      'assetPath': 'models/' + model.fileName,
      'destinationPath': destination.path,
      'expectedBytes': model.expectedBytesApprox,
      'expectedSha256': model.expectedSha256 ?? '',
    });

    if (!await isDownloaded(model)) {
      throw const FormatException(
        'The bundled model failed its size validation. Reinstall the app.',
      );
    }
    return destination;
  }

  Future<File> download(
    LocalModelSpec model, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
  }) async {
    final destination = await modelFile(model);
    if (await isDownloaded(model)) return destination;

    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.part');
    if (await temporary.exists()) await temporary.delete();

    try {
      final uri = Uri.parse(model.downloadUri);
      final response = await _client.send(http.Request('GET', uri));
      if (response.statusCode != HttpStatus.ok) {
        await response.stream.drain<void>();
        throw HttpException(
          'Model download failed with HTTP ${response.statusCode}.',
          uri: uri,
        );
      }

      final total = response.contentLength;
      var received = 0;
      final sink = temporary.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      final actualLength = await temporary.length();
      if (total != null && actualLength != total) {
        throw const FormatException(
          'Downloaded model size does not match the server response; please retry.',
        );
      }
      if (actualLength < model.expectedBytesApprox * 0.95) {
        throw const FormatException(
          'Downloaded model is smaller than expected; please retry.',
        );
      }

      // On Android's filesystem, rename within the same directory replaces
      // the destination atomically, avoiding a gap with no installed model.
      await temporary.rename(destination.path);
      return destination;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<void> delete(LocalModelSpec model) async {
    final file = await modelFile(model);
    if (await file.exists()) await file.delete();
    final partial = File('${file.path}.part');
    if (await partial.exists()) await partial.delete();
  }

  void dispose() => _client.close();
}
