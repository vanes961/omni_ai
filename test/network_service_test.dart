import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/core/network/mirror_resolver.dart';
import 'package:omni_ai/core/network/network_service.dart';

void main() {
  test('reports timed out requests to the critical failure handler', () async {
    NetworkException? reportedError;
    final service = NetworkService(
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response('', 200);
      }),
      timeout: const Duration(milliseconds: 1),
      onCriticalFailure: (error) => reportedError = error,
    );

    await expectLater(
      service.get(Uri.https('example.com', '/')),
      throwsA(
        isA<NetworkException>().having(
          (error) => error.isTimeout,
          'isTimeout',
          isTrue,
        ),
      ),
    );
    expect(reportedError?.isTimeout, isTrue);
  });

  test('resolver filters failed HTTP statuses and orders by latency', () async {
    final responses = <String, int>{
      'blocked.example': 403,
      'missing.example': 404,
      'slow.example': 200,
      'fast.example': 200,
    };
    final service = NetworkService(
      client: MockClient((request) async {
        return http.Response('', responses[request.url.host]!);
      }),
    );
    final resolver = MirrorResolver(
      networkService: service,
      probe: (uri) async {
        final response = await service.get(uri);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }
        return uri.host == 'fast.example'
            ? const Duration(milliseconds: 2)
            : const Duration(milliseconds: 10);
      },
    );
    final mirrors = responses.keys.map((host) => Uri.https(host, '/'));

    expect(await resolver.resolveAll(mirrors), [
      Uri.https('fast.example', '/'),
      Uri.https('slow.example', '/'),
    ]);
    expect(await resolver.resolve(mirrors), Uri.https('fast.example', '/'));
  });

  test('resolver reports when every mirror is unavailable', () async {
    final resolver = MirrorResolver(probe: (_) async => null);

    await expectLater(
      resolver.resolve([Uri.https('offline.example', '/')]),
      throwsStateError,
    );
  });
}
