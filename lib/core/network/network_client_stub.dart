import 'package:http/http.dart' as http;

import 'proxy_config.dart';

Map<String, String> defaultRequestHeaders() => const {};

http.Client createNetworkClient(ProxyConfig? proxyConfig) {
  if (proxyConfig?.enabled ?? false) {
    throw UnsupportedError(
      'Proxy configuration is unavailable on this platform.',
    );
  }
  return http.Client();
}
