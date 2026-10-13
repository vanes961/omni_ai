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
      throw const FormatException('TorrServer returned an unexpected response.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
