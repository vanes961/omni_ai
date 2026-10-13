import 'dart:convert';

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

  test('adds a magnet and parses the initial torrent status', () async {
    final magnet = Uri.parse(
      'magnet:?xt=urn:btih:0123456789012345678901234567890123456789&dn=Sample%20Film',
    );
    final client = TorrServerClient(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), 'http://media.example:8090/torrents');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['action'], 'add');
        expect(body['link'], magnet.toString());
        expect(body['title'], 'Sample Film');
        return http.Response(
          jsonEncode({
            'hash': '0123456789012345678901234567890123456789',
            'title': 'Sample Film',
            'stat_string': 'Torrent getting info',
            'file_stats': [],
          }),
          200,
        );
      }),
    );

    final info = await client.addMagnet(
      endpoint: 'http://media.example:8090',
      magnetUri: magnet,
      title: 'Sample Film',
    );

    expect(info.hash, '0123456789012345678901234567890123456789');
    expect(info.title, 'Sample Film');
    expect(info.status, 'Torrent getting info');
    expect(info.files, isEmpty);
  });

  test('rejects an invalid magnet without making a request', () async {
    var requestSent = false;
    final client = TorrServerClient(
      client: MockClient((_) async {
        requestSent = true;
        return http.Response('{}', 200);
      }),
    );

    expect(
      () => client.addMagnet(
        endpoint: 'http://media.example:8090',
        magnetUri: Uri.parse('https://example.com/video.mp4'),
      ),
      throwsArgumentError,
    );
    expect(requestSent, isFalse);
  });

  test('retrieves torrent files with server-provided indices and paths', () async {
    final client = TorrServerClient(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.toString(), 'http://media.example:8090/torrents');
        expect(jsonDecode(request.body), {
          'action': 'get',
          'hash': 'torrent-hash',
        });
        return http.Response(
          jsonEncode({
            'title': 'Example Series',
            'file_stats': [
              {'id': 0, 'path': 'Example Series/cover.jpg', 'length': 1200},
              {
                'id': 3,
                'path': 'Example Series/Season 1/Example.S01E02.mkv',
                'length': 1500000000,
              },
            ],
          }),
          200,
        );
      }),
    );

    final info = await client.getTorrentInfo(
      endpoint: 'http://media.example:8090',
      hash: 'torrent-hash',
    );

    expect(info, isNotNull);
    expect(info!.hash, 'torrent-hash');
    expect(info.title, 'Example Series');
    expect(info.files, hasLength(2));
    expect(info.files[0].id, 0);
    expect(info.files[0].path, 'Example Series/cover.jpg');
    expect(info.files[1].id, 3);
    expect(info.files[1].path, 'Example Series/Season 1/Example.S01E02.mkv');
    expect(info.files[1].length, 1500000000);
  });

  test('returns null when a torrent hash is not found', () async {
    final client = TorrServerClient(
      client: MockClient((_) async => http.Response('', 404)),
    );

    final info = await client.getTorrentInfo(
      endpoint: 'http://media.example:8090',
      hash: 'missing-hash',
    );

    expect(info, isNull);
  });

  test('surfaces TorrServer API errors with their response message', () async {
    final client = TorrServerClient(
      client: MockClient(
        (_) async => http.Response('{"error":"link is empty"}', 400),
      ),
    );

    await expectLater(
      client.addMagnet(
        endpoint: 'http://media.example:8090',
        magnetUri: Uri.parse(
          'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
        ),
      ),
      throwsA(
        isA<TorrServerApiException>()
            .having((error) => error.statusCode, 'statusCode', 400)
            .having((error) => error.message, 'message', 'link is empty'),
      ),
    );
  });
}
