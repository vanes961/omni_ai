import 'dart:async';

import 'package:omni_ai/features/media/data/torrserver_client.dart';
import 'package:omni_ai/features/media/data/torrserver_stream_resolver.dart';

/// Resolves a magnet into a playable TorrServer URL only after the server
/// reports a matching video file. It never silently chooses an arbitrary file
/// from a multi-video torrent.
class TorrServerFileSelectionRequired implements Exception {
  const TorrServerFileSelectionRequired(
    this.files, {
    required this.torrentHash,
  });

  final List<TorrServerFileStat> files;
  final String torrentHash;

  @override
  String toString() => 'Choose a video file from the torrent.';
}

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
    int? selectedFileIndex,
    String? existingTorrentHash,
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

    final initial = existingTorrentHash == null
        ? await _client.addMagnet(
            endpoint: endpoint,
            magnetUri: magnetUri,
            title: title,
            timeout: metadataTimeout,
          )
        : await _client.getTorrentInfo(
                endpoint: endpoint,
                hash: existingTorrentHash,
                timeout: metadataTimeout,
              ) ??
              (throw StateError(
                'TorrServer no longer has the selected torrent.',
              ));
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

    final selected = selectedFileIndex == null
        ? _selectFile(
            videos,
            episodeNumber: episodeNumber,
            seasonNumber: seasonNumber,
            torrentHash: info.hash,
          )
        : videos.firstWhere(
            (file) => file.id == selectedFileIndex,
            orElse: () => throw ArgumentError.value(
              selectedFileIndex,
              'selectedFileIndex',
              'The selected file is not a playable video in this torrent.',
            ),
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
    required String torrentHash,
  }) {
    if (episodeNumber == null) {
      if (videos.length == 1) return videos.single;
      throw TorrServerFileSelectionRequired(videos, torrentHash: torrentHash);
    }

    final normalizedPaths = {
      for (final file in videos)
        file: file.path.replaceAll(String.fromCharCode(92), '/'),
    };
    final episode = episodeNumber.toString();
    final season = seasonNumber?.toString();
    final seasonEpisodePatterns = <RegExp>[
      if (season != null)
        RegExp(
          r'(?:^|[/\s._-])s0*' + season + r'\s*e0*' + episode + r'(?:\D|$)',
          caseSensitive: false,
        ),
      if (season != null)
        RegExp(
          r'(?:^|[/\s._-])0*' + season + r'x0*' + episode + r'(?:\D|$)',
          caseSensitive: false,
        ),
      if (season != null)
        RegExp(
          r'season\s*0*' +
              season +
              r'[^0-9]{0,8}(?:episode|ep\.?|e)\s*0*' +
              episode +
              r'(?:\D|$)',
          caseSensitive: false,
        ),
    ];
    final episodePatterns = <RegExp>[
      RegExp(
        r'(?:episode\s*|ep\.?\s*|e)0*' + episode + r'(?:\D|$)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:^|[/\s._-])0*' + episode + r'(?:[/\s._-]|$)',
        caseSensitive: false,
      ),
    ];

    final seasonMatches = seasonEpisodePatterns.isEmpty
        ? <TorrServerFileStat>[]
        : videos
              .where(
                (file) => seasonEpisodePatterns.any(
                  (pattern) => pattern.hasMatch(normalizedPaths[file]!),
                ),
              )
              .toList(growable: false);
    if (seasonMatches.length == 1) return seasonMatches.single;
    if (seasonMatches.length > 1) {
      throw TorrServerFileSelectionRequired(videos, torrentHash: torrentHash);
    }

    final episodeMatches = videos
        .where((file) {
          final path = normalizedPaths[file]!;
          final basename = path.split('/').last;
          return episodePatterns.any((pattern) => pattern.hasMatch(basename));
        })
        .toList(growable: false);
    if (episodeMatches.length == 1) return episodeMatches.single;
    throw TorrServerFileSelectionRequired(videos, torrentHash: torrentHash);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
