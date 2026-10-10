import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Metadata for the first optional on-device model.
///
/// The model is downloaded separately from the APK to keep the installation
/// small. This service only manages the file; inference is handled separately.
class LocalModelCatalog {
  const LocalModelCatalog._();

  static const qwen3Small = LocalModelSpec(
    id: 'qwen3-0.6b-q4-k-m',
    displayName: 'Qwen3 0.6B (Q4_K_M)',
    fileName: 'Qwen3-0.6B-Q4_K_M.gguf',
    downloadUri:
        'https://huggingface.co/tensorblock/Qwen_Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
    expectedBytesApprox: 484000000,
  );
}

class LocalModelSpec {
  const LocalModelSpec({
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.downloadUri,
    required this.expectedBytesApprox,
  });

  final String id;
  final String displayName;
  final String fileName;
  final String downloadUri;
  final int expectedBytesApprox;
}

/// Stores optional GGUF files in app-private storage and downloads them on
/// demand. A `.part` file is used so interrupted downloads are never treated
/// as a complete model.
class LocalModelStorage {
  LocalModelStorage({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<File> modelFile(LocalModelSpec model) async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/models/${model.fileName}');
  }

  Future<bool> isDownloaded(LocalModelSpec model) async {
    final file = await modelFile(model);
    if (!await file.exists()) return false;
    final length = await file.length();
    return length > 0 && length >= model.expectedBytesApprox * 0.95;
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
    } catch (_) {
      await sink.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    await sink.close();

    final actualLength = await temporary.length();
    if (actualLength < model.expectedBytesApprox * 0.95) {
      await temporary.delete();
      throw const FormatException(
        'Downloaded model is smaller than expected; please retry.',
      );
    }

    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
    return destination;
  }

  Future<void> delete(LocalModelSpec model) async {
    final file = await modelFile(model);
    if (await file.exists()) await file.delete();
    final partial = File('${file.path}.part');
    if (await partial.exists()) await partial.delete();
  }

  void dispose() => _client.close();
}
