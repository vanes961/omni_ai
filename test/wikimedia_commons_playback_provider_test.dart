import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/media/data/source_discovery_service.dart';
import 'package:omni_ai/features/media/data/video_source_provider.dart';
import 'package:omni_ai/features/media/data/wikimedia_commons_playback_provider.dart';

void main() {
  group('Wikimedia Commons playback provider', () {
    const request = PlaybackRequest(
      mediaId: 'tmdb:movie:1',
      title: 'Open film',
      kind: PlaybackMediaKind.movie,
    );

    test('discovers a candidate only for supported media kinds', () async {
      final adapter = WikimediaCommonsDiscoveryAdapter();

      final movies = await adapter.discover(
        mediaKinds: const {PlaybackMediaKind.movie},
      );
      final series = await adapter.discover(
        mediaKinds: const {PlaybackMediaKind.series},
      );

      expect(movies.single.id, 'wikimedia-commons');
      expect(movies.single.capabilities,
          contains(DiscoveredSourceCapability.playback));
      expect(series, isEmpty);
    });

    test('returns only direct video URLs with recognized open licenses',
        () async {
      final client = MockClient((request) async {
        expect(request.url.host, 'commons.wikimedia.org');
        return http.Response(
          jsonEncode({
            'query': {
              'pages': {
                '1': {
                  'title': 'File:Open.webm',
                  'imageinfo': [
                    {
                      'url': 'https://upload.wikimedia.org/video/open.webm',
                      'extmetadata': {
                        'LicenseUrl': {
                          'value': 'https://creativecommons.org/licenses/by/4.0/',
                        },
                        'LicenseShortName': {'value': 'CC BY 4.0'},
                      },
                    },
                  ],
                },
                '2': {
                  'title': 'File:Unlicensed.mp4',
                  'imageinfo': [
                    {
                      'url': 'https://upload.wikimedia.org/video/unlicensed.mp4',
                      'extmetadata': {
                        'LicenseUrl': {'value': ''},
                        'LicenseShortName': {'value': 'All rights reserved'},
                      },
                    },
                  ],
                },
                '3': {
                  'title': 'File:External.webm',
                  'imageinfo': [
                    {
                      'url': 'https://example.org/external.webm',
                      'extmetadata': {
                        'LicenseUrl': {
                          'value': 'https://creativecommons.org/licenses/by/4.0/',
                        },
                      },
                    },
                  ],
                },
                '4': {
                  'title': 'File:Image.jpg',
                  'imageinfo': [
                    {
                      'url': 'https://upload.wikimedia.org/image.jpg',
                      'extmetadata': {
                        'LicenseUrl': {
                          'value': 'https://creativecommons.org/licenses/by/4.0/',
                        },
                      },
                    },
                  ],
                },
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final provider = WikimediaCommonsPlaybackProvider(client: client);

      final result = await provider.resolve(request);

      expect(result.variants, hasLength(1));
      expect(
        result.variants.single.url,
        'https://upload.wikimedia.org/video/open.webm',
      );
      expect(result.variants.single.format, 'webm');
    });

    test('does not resolve series because Commons is not configured for it',
        () async {
      var requested = false;
      final provider = WikimediaCommonsPlaybackProvider(
        client: MockClient((_) async {
          requested = true;
          return http.Response('{}', 200);
        }),
      );

      final result = await provider.resolve(
        const PlaybackRequest(
          mediaId: 'tmdb:series:1',
          title: 'Example series',
          kind: PlaybackMediaKind.series,
        ),
      );

      expect(requested, isFalse);
      expect(result.variants, isEmpty);
      expect(result.message, contains('только для фильмов и аниме'));
    });

    test('does not return streams when the API request fails', () async {
      final provider = WikimediaCommonsPlaybackProvider(
        client: MockClient((_) async => http.Response('unavailable', 503)),
      );

      final result = await provider.resolve(request);

      expect(result.variants, isEmpty);
      expect(result.message, contains('недоступен'));
    });
  });
}
