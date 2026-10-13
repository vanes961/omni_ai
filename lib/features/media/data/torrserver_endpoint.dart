import 'package:flutter/foundation.dart';

/// Validated base URL for a TorrServer instance.
@immutable
class TorrServerEndpoint {
  const TorrServerEndpoint._(this.baseUri);

  final Uri baseUri;

  /// Accepts only an absolute HTTP(S) origin without credentials, query or
  /// fragment. LAN HTTP endpoints are allowed for trusted home networks.
  static TorrServerEndpoint? tryParse(String value) {
    final input = value.trim();
    if (input.isEmpty || input.contains(RegExp(r'[\s\u0000-\u001f]'))) {
      return null;
    }

    final uri = Uri.tryParse(input);
    if (uri == null ||
        !uri.isAbsolute ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path.isNotEmpty && uri.path != '/') {
      return null;
    }

    if (uri.port < 1 || uri.port > 65535) return null;
    return TorrServerEndpoint._(
      Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null),
    );
  }

  Uri get echoUri => baseUri.resolve('/echo');

  @override
  String toString() => baseUri.toString();
}
