import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omni_ai/features/media/data/torrserver_endpoint.dart';
import 'package:omni_ai/features/media/domain/media_hub_contracts.dart';

class TorrServerHealthResult {
  const TorrServerHealthResult({
    required this.isAvailable,
    this.serverVersion,
    required this.message,
  });

  final bool isAvailable;
  final String? serverVersion;
  final String message;
}

/// One file advertised by TorrServer for a torrent.
class TorrServerFileStat {
  const TorrServerFileStat({
    required this.id,
    required this.path,
    required this.length,
  });

  /// TorrServer's file index. This is the value expected by /stream?index=.
  final int id;
  final String path;
  final int length;

  factory TorrServerFileStat.fromJson(Map<String, dynamic> json) {
    return TorrServerFileStat(
      id: (json['id'] as num?)?.toInt() ?? 0,
      path: json['path'] as String? ?? '',
      length: (json['length'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A snapshot returned by TorrServer's POST /torrents API.
class TorrServerTorrentInfo {
  const TorrServerTorrentInfo({
    required this.hash,
    required this.title,
    required this.files,
    this.status,
  });

  final String hash;
  final String title;
  final String? status;
  final List<TorrServerFileStat> files;

  factory TorrServerTorrentInfo.fromJson(
    Map<String, dynamic> json, {
    String fallbackHash = '',
  }) {
    final rawFiles = json['file_stats'];
    final files = rawFiles is List
        ? rawFiles
              .whereType<Map>()
              .map(
                (file) => TorrServerFileStat.fromJson(
                  Map<String, dynamic>.from(file),
                ),
              )
              .toList(growable: false)
        : const <TorrServerFileStat>[];

    return TorrServerTorrentInfo(
      hash: json['hash'] as String? ?? fallbackHash,
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      status: json['stat_string'] as String?,
      files: files,
    );
  }
}

class TorrServerApiException implements Exception {
  const TorrServerApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'TorrServerApiException($statusCode): $message';
}

/// TorrServer client for health checks and torrent file discovery.
///
/// API methods use POST /torrents; the server returns file_stats with the
/// explicit file indices required to play a chosen episode via /stream.
class TorrServerClient {
  TorrServerClient({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Future<TorrServerHealthResult> checkConnection(
    String endpoint, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final config = TorrServerEndpoint.tryParse(endpoint);
    if (config == null) {
      return const TorrServerHealthResult(
        isAvailable: false,
        message: 'Укажите корректный адрес HTTP(S) без логина и пароля',
      );
    }

    try {
      final response = await _client.get(config.echoUri).timeout(timeout);
      if (response.statusCode != 200) {
        return TorrServerHealthResult(
          isAvailable: false,
          message: 'TorrServer ответил HTTP ${response.statusCode}',
        );
      }

      final version = response.body.trim();
      return TorrServerHealthResult(
        isAvailable: true,
        serverVersion: version.isEmpty ? null : version,
        message: version.isEmpty
            ? 'TorrServer доступен'
            : 'TorrServer доступен · $version',
      );
    } on TimeoutException {
      return const TorrServerHealthResult(
        isAvailable: false,
        message: 'Превышено время ожидания ответа TorrServer',
      );
    } on Object {
      return const TorrServerHealthResult(
        isAvailable: false,
        message: 'Не удалось подключиться к TorrServer',
      );
    }
  }

  /// Adds a magnet to TorrServer and returns its initial status.
  ///
  /// TorrServer may still be resolving metadata; call [getTorrentInfo] again
  /// until [TorrServerTorrentInfo.files] is populated.
  Future<TorrServerTorrentInfo> addMagnet({
    required String endpoint,
    required Uri magnetUri,
    String? title,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final config = _requireEndpoint(endpoint);
    final source = MediaStreamSource(
      id: 'torrent-source',
      label: title ?? 'User-provided torrent',
      uri: magnetUri,
    );
    if (!source.isMagnet) {
      throw ArgumentError.value(
        magnetUri,
        'magnetUri',
        'Must contain a valid BitTorrent info hash.',
      );
    }

    final response = await _client
        .post(
          config.baseUri.resolve('/torrents'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'action': 'add',
            'link': magnetUri.toString(),
            if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
          }),
        )
        .timeout(timeout);
    final json = _decodeResponse(response);
    return TorrServerTorrentInfo.fromJson(json);
  }

  /// Reads the current status and file list for a torrent already added.
  ///
  /// Returns null when TorrServer responds with HTTP 404 for the hash.
  Future<TorrServerTorrentInfo?> getTorrentInfo({
    required String endpoint,
    required String hash,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final config = _requireEndpoint(endpoint);
    if (hash.trim().isEmpty) {
      throw ArgumentError.value(hash, 'hash', 'Must not be empty.');
    }

    final response = await _client
        .post(
          config.baseUri.resolve('/torrents'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'action': 'get', 'hash': hash.trim()}),
        )
        .timeout(timeout);
    if (response.statusCode == 404) return null;

    final json = _decodeResponse(response);
    return TorrServerTorrentInfo.fromJson(json, fallbackHash: hash.trim());
  }

  TorrServerEndpoint _requireEndpoint(String endpoint) {
    final config = TorrServerEndpoint.tryParse(endpoint);
    if (config == null) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Must be a valid HTTP(S) TorrServer root URL without credentials.',
      );
    }
    return config;
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = response.body.trim();
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] is String) {
          message = body['error'] as String;
        }
      } on FormatException {
        // Keep the plain-text response as the diagnostic message.
      }
      throw TorrServerApiException(
        response.statusCode,
        message.isEmpty ? 'TorrServer request failed' : message,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException(
        'TorrServer returned an unexpected response.',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
import 'dart:async';

import 'package:omni_ai/features/media/data/torrserver_client.dart';
import 'package:omni_ai/features/media/data/torrserver_stream_resolver.dart';

/// Resolves a magnet into a playable TorrServer URL only after the server
/// reports a matching video file. It never silently chooses an arbitrary file
/// from a multi-video torrent.
class TorrServerPlaybackResolver {
  TorrServerPlaybackResolver({
    TorrServerClient? client,
    TorrServerStreamResolver streamResolver = const TorrServerStreamResolver(),
    Future<void> Function(Duration)? wait,
  }) : _client = client ?? TorrServerClient(),
       _ownsClient = client == null,
       _streamResolver = streamResolver,
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
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
