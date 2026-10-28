import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/media/data/torrserver_client.dart';
import 'package:omni_ai/features/media/data/torrserver_playback_resolver.dart';

void main() {
  const endpoint = 'http://127.0.0.1:8090';
  final magnet = Uri.parse(
    'magnet:?xt=urn:btih:0123456789012345678901234567890123456789&dn=Licensed%20Test',
  );

  MockClient clientWithFiles(List<Map<String, Object>> files) {
    return MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/torrents');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['action'], 'add');
      return http.Response(
        jsonEncode({
          'hash': '0123456789012345678901234567890123456789',
          'title': 'Licensed Test',
          'file_stats': files,
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });
  }

  test('selects the requested season and episode from real file metadata', () async {
    final client = clientWithFiles([
      {'id': 0, 'path': 'Licensed Test/trailer.mp4', 'length': 100},
      {'id': 1, 'path': 'Licensed Test/Season 02/Show.S02E03.1080p.mkv', 'length': 200},
      {'id': 2, 'path': 'Licensed Test/Season 02/Show.S02E04.1080p.mkv', 'length': 300},
      {'id': 3, 'path': 'Licensed Test/readme.txt', 'length': 10},
    ]);
    final resolver = TorrServerPlaybackResolver(
      client: TorrServerClient(client: client),
    );

    final stream = await resolver.resolve(
      endpoint: endpoint,
      magnetUri: magnet,
      title: 'Licensed Test',
      seasonNumber: 2,
      episodeNumber: 3,
    );

    expect(stream.path, '/stream');
    expect(stream.queryParameters['index'], '1');
    expect(stream.queryParameters['play'], 'true');
    resolver.close();
    client.close();
  });

  test('requires explicit selection when episode matching is ambiguous', () async {
    final client = clientWithFiles([
      {'id': 1, 'path': 'Show.S01E02.720p.mkv', 'length': 200},
      {'id': 2, 'path': 'Extras/Show.S01E02.DirectorsCut.mp4', 'length': 300},
    ]);
    final resolver = TorrServerPlaybackResolver(
      client: TorrServerClient(client: client),
    );

    await expectLater(
      resolver.resolve(
        endpoint: endpoint,
        magnetUri: magnet,
        seasonNumber: 1,
        episodeNumber: 2,
      ),
      throwsA(isA<TorrServerFileSelectionRequired>()),
    );
    resolver.close();
    client.close();
  });

  test('requires explicit selection for a multi-video movie torrent', () async {
    final client = clientWithFiles([
      {'id': 1, 'path': 'Movie/Feature.mkv', 'length': 200},
      {'id': 2, 'path': 'Movie/Bonus.mp4', 'length': 50},
    ]);
    final resolver = TorrServerPlaybackResolver(
      client: TorrServerClient(client: client),
    );

    await expectLater(
      resolver.resolve(endpoint: endpoint, magnetUri: magnet),
      throwsA(isA<TorrServerFileSelectionRequired>()),
    );
    resolver.close();
    client.close();
  });
}
