import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/media/data/peertube_directory_playback_provider.dart';
import 'package:omni_ai/features/media/data/source_discovery_service.dart';
import 'package:omni_ai/features/media/data/video_source_provider.dart';

void main() {
  group('PeerTube directory playback provider', () {
    test('discovers one automatic directory adapter for video media', () async {
      final adapter = PeerTubeDirectoryDiscoveryAdapter();
      final candidates = await adapter.discover(
        mediaKinds: const {
          PlaybackMediaKind.movie,
          PlaybackMediaKind.series,
          PlaybackMediaKind.anime,
        },
      );
      final none = await adapter.discover(
        mediaKinds: const <PlaybackMediaKind>{},
      );

      expect(candidates.single.id, 'peertube-directory');
      expect(candidates.single.baseUri.scheme, 'https');
      expect(
        candidates.single.capabilities,
        contains(DiscoveredSourceCapability.playback),
      );
      expect(none, isEmpty);
    });

    test('probes directory only when it returns a valid host', () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'instances.joinpeertube.org');
        expect(request.url.path, '/api/v1/instances');
        return http.Response(
          jsonEncode({
            'data': [
              {'host': 'videos.example.org', 'totalVideos': 100},
            ],
          }),
          200,
        );
      });
      final candidate = (await PeerTubeDirectoryDiscoveryAdapter().discover(
        mediaKinds: const {PlaybackMediaKind.movie},
      )).single;
      final checked = await PeerTubeDirectoryProbe(client: client).check(
        candidate,
      );

      expect(checked.status, DiscoveredSourceStatus.available);
    });

    test('rejects private and numeric IPv4 hosts from the directory', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'data': [
              {'host': '172.16.0.10', 'totalVideos': 100},
              {'host': '172.31.255.1', 'totalVideos': 100},
              {'host': '192.168.1.20', 'totalVideos': 100},
              {'host': '203.0.113.10', 'totalVideos': 100},
            ],
          }),
          200,
        );
      });
      final candidate = (await PeerTubeDirectoryDiscoveryAdapter().discover(
        mediaKinds: const {PlaybackMediaKind.movie},
      )).single;
      final checked = await PeerTubeDirectoryProbe(client: client).check(
        candidate,
      );

      expect(checked.status, DiscoveredSourceStatus.unavailable);
    });

    test(
      'returns only same-host video streams with explicit open licences',
      () async {
      final client = MockClient((request) async {
        if (request.url.host == 'instances.joinpeertube.org') {
          return http.Response(
            jsonEncode({
              'data': [
                {'host': 'videos.example.org', 'totalVideos': 100},
              ],
            }),
            200,
          );
        }
        expect(request.url.host, 'videos.example.org');
        expect(request.url.path, '/api/v1/search/videos');
        return http.Response(
          jsonEncode({
            'data': [
              {
                'licence': {'id': 2, 'label': 'Attribution - Share Alike'},
                'files': [
                  {
                    'fileUrl': 'https://videos.example.org/static/open.mp4',
                    'resolution': {'id': 720, 'label': '720p'},
                  },
                  {
                    'fileUrl': 'https://evil.example/static/external.mp4',
                    'resolution': {'id': 1080, 'label': '1080p'},
                  },
                ],
                'streamingPlaylists': [
                  {
                    'playlistUrl': 'https://videos.example.org/static/open.m3u8',
                  },
                ],
              },
              {
                'licence': {'id': 9, 'label': 'All Rights Reserved'},
                'files': [
                  {'fileUrl': 'https://videos.example.org/static/unknown.mp4'},
                ],
              },
            ],
          }),
          200,
        );
      });
      final provider = PeerTubeDirectoryPlaybackProvider(client: client);
      const request = PlaybackRequest(
        mediaId: 'tmdb:movie:1',
        title: 'Open film',
        kind: PlaybackMediaKind.movie,
      );

      final result = await provider.resolve(request);

      expect(result.variants, hasLength(2));
      expect(
        result.variants.map((variant) => variant.url),
        containsAll([
          'https://videos.example.org/static/open.mp4',
          'https://videos.example.org/static/open.m3u8',
        ]),
      );
      expect(
        result.variants.any((variant) => variant.url.contains('evil')),
        isFalse,
      );
      expect(
        result.variants.any((variant) => variant.url.contains('unknown')),
        isFalse,
      );
    });

    test('does not return results when the directory is unavailable', () async {
      final provider = PeerTubeDirectoryPlaybackProvider(
        client: MockClient((_) async => http.Response('offline', 503)),
      );
      final result = await provider.resolve(
        const PlaybackRequest(
          mediaId: 'tmdb:movie:1',
          title: 'Open film',
          kind: PlaybackMediaKind.movie,
        ),
      );

      expect(result.variants, isEmpty);
      expect(result.message, contains('недоступен'));
    });
  });
}
