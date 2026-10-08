import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

import 'proxy_config.dart';

Map<String, String> defaultRequestHeaders() => const {};

http.Client createNetworkClient(ProxyConfig? proxyConfig) {
  if (proxyConfig?.enabled ?? false) {
    throw UnsupportedError(
      'Browser proxy settings are controlled by the browser.',
    );
  }
  return BrowserClient();
}
