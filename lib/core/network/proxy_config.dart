enum ProxyType { http, socks5, mtproto }

class ProxyConfig {
  const ProxyConfig({
    required this.type,
    required this.host,
    required this.port,
    this.username,
    this.password,
    this.enabled = true,
  });

  final ProxyType type;
  final String host;
  final int port;
  final String? username;
  final String? password;
  final bool enabled;

  Uri get uri => Uri(
    scheme: switch (type) {
      ProxyType.http => 'http',
      ProxyType.socks5 => 'socks5',
      ProxyType.mtproto => 'mtproto',
    },
    host: host,
    port: port,
  );
}
