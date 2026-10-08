import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'network_client_stub.dart'
    if (dart.library.io) 'network_client_io.dart'
    if (dart.library.html) 'network_client_web.dart'
    as transport;
import 'proxy_config.dart';

typedef AIGuardNetworkHandler = FutureOr<void> Function(NetworkException error);

class NetworkService {
  const NetworkService({
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.onCriticalFailure,
  }) : _providedClient = client,
       _ownsClient = false,
       proxyConfig = null;

  NetworkService.withProxy({
    required this.proxyConfig,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
    this.onCriticalFailure,
  }) : _providedClient = client ?? transport.createNetworkClient(proxyConfig),
       _ownsClient = client == null;

  final http.Client? _providedClient;
  final bool _ownsClient;
  final Duration timeout;
  final ProxyConfig? proxyConfig;
  final AIGuardNetworkHandler? onCriticalFailure;

  static final http.Client _defaultClient = transport.createNetworkClient(null);

  static Map<String, String> get defaultHeaders =>
      Map.unmodifiable(transport.defaultRequestHeaders());

  http.Client get _client => _providedClient ?? _defaultClient;

  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) {
    return _run(uri, () => _client.get(uri, headers: _mergeHeaders(headers)));
  }

  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _run(
      uri,
      () => _client.post(uri, headers: _mergeHeaders(headers), body: body),
    );
  }

  Future<http.Response> send(http.BaseRequest request) {
    for (final entry in transport.defaultRequestHeaders().entries) {
      if (!request.headers.containsKey(entry.key)) {
        request.headers[entry.key] = entry.value;
      }
    }
    return _run(
      request.url,
      () async => http.Response.fromStream(await _client.send(request)),
    );
  }

  Map<String, String> _mergeHeaders(Map<String, String>? headers) {
    final merged = Map<String, String>.from(transport.defaultRequestHeaders());
    if (headers != null) {
      for (final entry in headers.entries) {
        merged.removeWhere(
          (name, _) => name.toLowerCase() == entry.key.toLowerCase(),
        );
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  Future<http.Response> _run(
    Uri uri,
    Future<http.Response> Function() sendRequest,
  ) async {
    try {
      return await sendRequest().timeout(timeout);
    } on TimeoutException catch (error) {
      throw await _report(
        NetworkException(
          uri: uri,
          message: 'Request timed out after ${timeout.inSeconds} seconds.',
          cause: error,
          isTimeout: true,
        ),
      );
    } on SocketException catch (error) {
      throw await _report(
        NetworkException(
          uri: uri,
          message: 'Network connection failed.',
          cause: error,
        ),
      );
    } on http.ClientException catch (error) {
      throw await _report(
        NetworkException(
          uri: uri,
          message: 'HTTP request failed.',
          cause: error,
        ),
      );
    }
  }

  Future<NetworkException> _report(NetworkException error) async {
    try {
      await onCriticalFailure?.call(error);
    } on Object {
      // AIGuard reporting must not hide the original network failure.
    }
    return error;
  }

  void close() {
    if (_ownsClient) _providedClient!.close();
  }
}

class NetworkException implements Exception {
  const NetworkException({
    required this.uri,
    required this.message,
    this.cause,
    this.isTimeout = false,
  });

  final Uri uri;
  final String message;
  final Object? cause;
  final bool isTimeout;

  @override
  String toString() => 'NetworkException: $message ($uri)';
}
