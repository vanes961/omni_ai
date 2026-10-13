import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/media/data/torrserver_playback_resolver.dart';
import 'package:omni_ai/features/media/data/torrserver_client.dart';

const _magnet =
    'magnet:?xt=urn:btih:0123456789012345678901234567890123456789&dn=Example';

void main() {
  test('resolves a single video file after metadata becomes available', () async {
    var getCount = 0;
    final resolver = TorrServerPlaybackResolver(
      client: TorrServerClient(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['action'] == 'add') {
            return http.Response(
              jsonEncode({
                'hash': 'torrent-hash',
                'title': 'Example Film',
                'file_stats': [],
              }),
              200,
            );
          }
          getCount++;
          return http.Response(
            jsonEncode({
              'hash': 'torrent-hash',
              'title': 'Example Film',
              'file_stats': [
                {'id': 4, 'path': 'Example Film.mkv', 'length': 1000},
              ],
            }),
            200,
          );
        }),
      ),
      wait: (_) async {},
    );

    final uri = await resolver.resolve(
      endpoint: 'http://media.example:8090',
      magnetUri: Uri.parse(_magnet),
      title: 'Example Film',
    );

    expect(getCount, 1);
    expect(uri.path, '/stream');
    expect(uri.queryParameters['index'], '4');
    expect(uri.queryParameters['link'], _magnet);
  });

  test('selects the requested episode by filename, not list position', () async {
    final resolver = TorrServerPlaybackResolver(
      client: TorrServerClient(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['action'] == 'add') {
            return http.Response(
              jsonEncode({'hash': 'series-hash', 'file_stats': []}),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'hash': 'series-hash',
              'file_stats': [
                {'id': 0, 'path': 'Series/cover.jpg', 'length': 500},
                {'id': 1, 'path': 'Series/Series.S01E01.mkv', 'length': 1000},
                {'id': 7, 'path': 'Series/Series.S01E02.mkv', 'length': 1000},
              ],
            }),
            200,
          );
        }),
      ),
      wait: (_) async {},
    );

    final uri = await resolver.resolve(
      endpoint: 'http://media.example:8090',
      magnetUri: Uri.parse(_magnet),
      episodeNumber: 2,
      seasonNumber: 1,
    );

    expect(uri.queryParameters['index'], '7');
  });

  test('does not choose the first file when multiple videos have no episode', () async {
    final resolver = TorrServerPlaybackResolver(
      client: TorrServerClient(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['action'] == 'add') {
            return http.Response(
              jsonEncode({'hash': 'multi-hash', 'file_stats': []}),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'hash': 'multi-hash',
              'file_stats': [
                {'id': 1, 'path': 'one.mkv', 'length': 1000},
                {'id': 2, 'path': 'two.mp4', 'length': 1000},
              ],
            }),
            200,
          );
        }),
      ),
      wait: (_) async {},
    );

    await expectLater(
      resolver.resolve(
        endpoint: 'http://media.example:8090',
        magnetUri: Uri.parse(_magnet),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
