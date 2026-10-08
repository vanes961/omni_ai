import 'dart:io';

import 'package:http/io_client.dart';
import 'package:http/http.dart' as http;

import 'proxy_config.dart';

http.Client createNetworkClient(ProxyConfig? proxyConfig) {
  final config = proxyConfig;
  if (config == null || !config.enabled) return IOClient(HttpClient());

  if (config.type != ProxyType.http) {
    throw UnsupportedError(
      '${config.type.name} proxy transport is not implemented yet.',
    );
  }

  final httpClient = HttpClient()
    ..findProxy = (_) => 'PROXY ${config.host}:${config.port}';
  if (config.username != null) {
    httpClient.addProxyCredentials(
      config.host,
      config.port,
      '',
      HttpClientBasicCredentials(config.username!, config.password ?? ''),
    );
  }
  return IOClient(httpClient);
}
