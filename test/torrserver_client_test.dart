import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/media/data/torrserver_client.dart';

void main() {
  test('checks the documented /echo endpoint and returns server version', () async {
    final client = TorrServerClient(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'http://192.168.1.20:8090/echo');
        return http.Response('TorrServer 136.0', 200);
      }),
    );

    final result = await client.checkConnection('http://192.168.1.20:8090');

    expect(result.isAvailable, isTrue);
    expect(result.serverVersion, 'TorrServer 136.0');
    expect(result.message, contains('TorrServer доступен'));
  });

  test('reports a non-success HTTP response as unavailable', () async {
    final client = TorrServerClient(
      client: MockClient((_) async => http.Response('Unauthorized', 401)),
    );

    final result = await client.checkConnection('http://media.example:8090');

    expect(result.isAvailable, isFalse);
    expect(result.message, contains('401'));
  });

  test('does not send requests for an invalid endpoint', () async {
    var requestSent = false;
    final client = TorrServerClient(
      client: MockClient((_) async {
        requestSent = true;
        return http.Response('unexpected', 200);
      }),
    );

    final result = await client.checkConnection('http://user:pass@media.example');

    expect(result.isAvailable, isFalse);
    expect(requestSent, isFalse);
  });
}
