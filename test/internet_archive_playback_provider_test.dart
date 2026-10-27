import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/media/data/internet_archive_playback_provider.dart';
import 'package:omni_ai/features/media/data/source_discovery_service.dart';
import 'package:omni_ai/features/media/data/video_source_engine.dart';
import 'package:omni_ai/features/media/data/video_source_provider.dart';

void main() {
  test('discovers and validates the Internet Archive provider', () async {
    final client = MockClient((request) async => http.Response('ok', 200));
    final engine = VideoSourceEngine([]);
    final service = SourceDiscoveryService(
      adapters: [InternetArchiveDiscoveryAdapter()],
      probe: InternetArchiveSourceProbe(client: client),
      videoSourceEngine: engine,
      providerFactory: (candidate) => candidate.id == 'internet-archive'
          ? InternetArchivePlaybackProvider(client: client)
          : null,
      rejectionStore: _MemoryRejectionStore(),
    );

    final candidates = await service.discoverAndCheck();

    expect(candidates.single.status, DiscoveredSourceStatus.available);
    expect(engine.providerIds, contains('internet-archive'));
  });

  test('resolves only files with an explicitly recognized open license', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/advancedsearch.php') {
        return http.Response(
          jsonEncode({
            'response': {
              'docs': [
                {'identifier': 'open-film', 'title': 'Open Film'},
                {'identifier': 'unknown-film', 'title': 'Unknown Film'},
              ],
            },
          }),
          200,
        );
      }
      if (request.url.path == '/metadata/open-film') {
        return http.Response(
          jsonEncode({
            'metadata': {
              'title': 'Open Film',
              'licenseurl': 'https://creativecommons.org/publicdomain/mark/1.0/',
            },
            'files': [
              {'name': 'Open Film.mp4', 'size': '1000'},
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/metadata/unknown-film') {
        return http.Response(
          jsonEncode({
            'metadata': {'title': 'Unknown Film'},
            'files': [
              {'name': 'Unknown Film.mp4', 'size': '1000'},
            ],
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final provider = InternetArchivePlaybackProvider(client: client);

    final result = await provider.resolve(
      const PlaybackRequest(
        mediaId: 'tmdb:movie:1',
        title: 'Open Film',
        kind: PlaybackMediaKind.movie,
      ),
    );

    expect(result.variants, hasLength(1));
    expect(result.variants.single.url, contains('archive.org/download/open-film/'));
    expect(result.variants.single.isHttpStream, isTrue);
  });

  test('does not resolve series through the movie-only provider', () async {
    final provider = InternetArchivePlaybackProvider(
      client: MockClient((_) async => http.Response('unexpected', 500)),
    );

    final result = await provider.resolve(
      const PlaybackRequest(
        mediaId: 'series:1',
        title: 'Series',
        kind: PlaybackMediaKind.series,
        season: 1,
        episode: 1,
      ),
    );

    expect(result.variants, isEmpty);
  });
}

class _MemoryRejectionStore implements SourceDiscoveryRejectionStore {
  final Map<String, String> values = {};

  @override
  Future<Map<String, String>> load() async => Map.of(values);

  @override
  Future<void> save(Map<String, String> rejections) async {
    values
      ..clear()
      ..addAll(rejections);
  }
}
