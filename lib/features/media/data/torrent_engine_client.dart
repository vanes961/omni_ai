import 'package:flutter/services.dart';

/// Flutter-facing API for the native, standalone libtorrent4j session.
///
/// The native engine currently resolves magnet metadata and manages file
/// priorities. Playback through a local byte-range endpoint is a later stage.
class TorrentEngineClient {
  TorrentEngineClient({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('omni_ai/torrent_engine');

  final MethodChannel _channel;

  Future<void> startMagnet(String magnetUri) async {
    final value = magnetUri.trim();
    if (value.isEmpty || value.length > 4096) {
      throw ArgumentError.value(magnetUri, 'magnetUri', 'Invalid magnet URI length.');
    }
    await _channel.invokeMapMethod<String, dynamic>(
      'startMagnet',
      <String, Object?>{'magnetUri': value},
    );
  }

  Future<TorrentEngineStatus> getStatus() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getTorrentStatus',
    );
    return TorrentEngineStatus.fromMap(result ?? const <String, dynamic>{});
  }

  Future<List<TorrentEngineFile>> listFiles() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'listTorrentFiles',
    );
    final rawFiles = result?['files'];
    if (rawFiles is! List) return const <TorrentEngineFile>[];
    return rawFiles
        .whereType<Map<Object?, Object?>>()
        .map(TorrentEngineFile.fromMap)
        .toList(growable: false);
  }

  Future<void> selectFile(int index) async {
    if (index < 0) {
      throw ArgumentError.value(index, 'index', 'Must be non-negative.');
    }
    await _channel.invokeMapMethod<String, dynamic>(
      'selectTorrentFile',
      <String, Object?>{'index': index},
    );
  }

  Future<void> stopTorrent() async {
    await _channel.invokeMapMethod<String, dynamic>('stopTorrent');
  }
}

class TorrentEngineStatus {
  const TorrentEngineStatus({
    required this.metadataReady,
    required this.progress,
    required this.downloadRateBytesPerSecond,
    required this.downloadedBytes,
    required this.finished,
    this.name,
    this.fileCount = 0,
  });

  final bool metadataReady;
  final double progress;
  final int downloadRateBytesPerSecond;
  final int downloadedBytes;
  final bool finished;
  final String? name;
  final int fileCount;

  factory TorrentEngineStatus.fromMap(Map<String, dynamic> map) {
    return TorrentEngineStatus(
      metadataReady: map['metadataReady'] == true,
      progress: (map['progress'] as num?)?.toDouble() ?? 0,
      downloadRateBytesPerSecond:
          (map['downloadRateBytesPerSecond'] as num?)?.toInt() ?? 0,
      downloadedBytes: (map['downloadedBytes'] as num?)?.toInt() ?? 0,
      finished: map['finished'] == true,
      name: map['name'] as String?,
      fileCount: (map['fileCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class TorrentEngineFile {
  const TorrentEngineFile({
    required this.index,
    required this.path,
    required this.name,
    required this.sizeBytes,
  });

  final int index;
  final String path;
  final String name;
  final int sizeBytes;

  factory TorrentEngineFile.fromMap(Map<Object?, Object?> map) {
    return TorrentEngineFile(
      index: (map['index'] as num?)?.toInt() ?? -1,
      path: map['path'] as String? ?? '',
      name: map['name'] as String? ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}
