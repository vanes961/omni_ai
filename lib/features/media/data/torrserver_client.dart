import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:omni_ai/features/media/data/torrserver_endpoint.dart';

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

/// Minimal TorrServer health client. It uses the documented GET /echo endpoint
/// and never logs or embeds credentials in the URL.
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
      final response = await _client
          .get(config.echoUri)
          .timeout(timeout);
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

  void close() {
    if (_ownsClient) _client.close();
  }
}
