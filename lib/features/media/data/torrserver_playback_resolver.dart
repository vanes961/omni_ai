import 'dart:async';

import 'package:omni_ai/features/media/data/torrserver_client.dart';
import 'package:omni_ai/features/media/data/torrserver_stream_resolver.dart';

/// Resolves a magnet into a playable TorrServer URL only after the server
/// reports a matching video file. It never silently chooses an arbitrary file
/// from a multi-video torrent.
class TorrServerPlaybackResolver {
  TorrServerPlaybackResolver({
    TorrServerClient? client,
    this._streamResolver = const TorrServerStreamResolver(),
    Future<void> Function(Duration)? wait,
  }) : _client = client ?? TorrServerClient(),
       _ownsClient = client == null,
       _wait = wait ?? Future<void>.delayed;

  final TorrServerClient _client;
  final bool _ownsClient;
  final TorrServerStreamResolver _streamResolver;
  final Future<void> Function(Duration) _wait;

  static const _videoExtensions = <String>{
    '.mkv',
    '.mp4',
    '.m4v',
    '.avi',
    '.mov',
    '.webm',
    '.ts',
    '.m2ts',
    '.mpg',
    '.mpeg',
  };

  Future<Uri> resolve({
    required String endpoint,
    required Uri magnetUri,
    String? title,
    int? episodeNumber,
    int? seasonNumber,
    Duration metadataTimeout = const Duration(seconds: 30),
    Duration pollInterval = const Duration(seconds: 1),
  }) async {
    if (episodeNumber != null && episodeNumber < 1) {
      throw ArgumentError.value(episodeNumber, 'episodeNumber');
    }
    if (seasonNumber != null && seasonNumber < 1) {
      throw ArgumentError.value(seasonNumber, 'seasonNumber');
    }
    if (metadataTimeout <= Duration.zero || pollInterval <= Duration.zero) {
      throw ArgumentError(
        'Metadata timeout and poll interval must be positive.',
      );
    }

    final initial = await _client.addMagnet(
      endpoint: endpoint,
      magnetUri: magnetUri,
      title: title,
      timeout: metadataTimeout,
    );
    if (initial.hash.trim().isEmpty) {
      throw const FormatException(
        'TorrServer did not return the torrent hash; cannot query its files.',
      );
    }

    final deadline = DateTime.now().add(metadataTimeout);
    var info = initial;
    while (info.files.isEmpty && DateTime.now().isBefore(deadline)) {
      await _wait(pollInterval);
      final updated = await _client.getTorrentInfo(
        endpoint: endpoint,
        hash: initial.hash,
        timeout: metadataTimeout,
      );
      if (updated == null) {
        throw StateError('TorrServer no longer has the added torrent.');
      }
      info = updated;
    }

    final videos = info.files
        .where((file) => _isVideoFile(file.path))
        .toList(growable: false);
    if (videos.isEmpty) {
      throw StateError('TorrServer has not reported any playable video files.');
    }

    final selected = _selectFile(
      videos,
      episodeNumber: episodeNumber,
      seasonNumber: seasonNumber,
    );
    return _streamResolver.resolve(
      endpoint: endpoint,
      magnetUri: magnetUri,
      fileIndex: selected.id,
    );
  }

  bool _isVideoFile(String path) {
    final normalized = path.toLowerCase().split('?').first;
    return _videoExtensions.any(normalized.endsWith);
  }

  TorrServerFileStat _selectFile(
    List<TorrServerFileStat> videos, {
    int? episodeNumber,
    int? seasonNumber,
  }) {
    if (episodeNumber == null) {
      if (videos.length == 1) return videos.single;
      throw StateError(
        'Torrent contains multiple videos; choose a specific episode/file.',
      );
    }

    final episode = episodeNumber.toString().padLeft(2, '0');
    final season = seasonNumber?.toString().padLeft(2, '0');
    final patterns = <RegExp>[
      if (season != null)
        RegExp(
          r'(?:s|season\s*)' +
              season +
              r'[^0-9]{0,4}(?:e|episode\s*)' +
              episode +
              r'(?:\D|$)',
          caseSensitive: false,
        ),
      RegExp(
        r'(?:s\d{1,2}e|episode\s*|ep\.?\s*)' + episode + r'(?:\D|$)',
        caseSensitive: false,
      ),
      RegExp(r'(?<!\d)' + episodeNumber.toString() + r'(?!\d)'),
    ];
    final matches = videos
        .where((file) => patterns.any((pattern) => pattern.hasMatch(file.path)))
        .toList(growable: false);
    if (matches.length == 1) return matches.single;
    if (matches.isEmpty) {
      throw StateError(
        'Could not match episode $episodeNumber to a file in the torrent.',
      );
    }
    throw StateError(
      'More than one torrent file matches episode $episodeNumber.',
    );
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
