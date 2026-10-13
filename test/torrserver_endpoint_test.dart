import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/data/torrserver_endpoint.dart';

void main() {
  group('TorrServerEndpoint', () {
    test('accepts a local HTTP endpoint and builds the documented echo URL', () {
      final endpoint = TorrServerEndpoint.tryParse('http://192.168.1.20:8090/');

      expect(endpoint, isNotNull);
      expect(endpoint!.baseUri.toString(), 'http://192.168.1.20:8090');
      expect(endpoint.echoUri.toString(), 'http://192.168.1.20:8090/echo');
    });

    test('accepts HTTPS and default ports', () {
      final endpoint = TorrServerEndpoint.tryParse('https://media.example');

      expect(endpoint?.baseUri.toString(), 'https://media.example');
      expect(endpoint?.echoUri.scheme, 'https');
    });

    test('rejects credentials, query, fragment, paths and non-HTTP schemes', () {
      for (final value in [
        'http://user:pass@media.example:8090',
        'http://media.example:8090?token=secret',
        'http://media.example:8090/#fragment',
        'http://media.example:8090/api',
        'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
        'not a URL',
      ]) {
        expect(
          TorrServerEndpoint.tryParse(value),
          isNull,
          reason: 'Should reject $value',
        );
      }
    });

    test('rejects invalid ports', () {
      expect(TorrServerEndpoint.tryParse('http://media.example:99999'), isNull);
    });
  });
}
