import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/media/services/ani_skip_segment_provider.dart';
import 'package:omni_ai/features/media/services/media_segment_marker_store.dart';

void main() {
  test('maps AniSkip opening and ending timestamps to local duration', () async {
    Uri? requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(
        jsonEncode({
          'found': true,
          'results': [
            {
              'skipType': 'op',
              'episodeLength': 1400,
              'interval': {'startTime': 90.0, 'endTime': 180.0},
            },
            {
              'skipType': 'ed',
              'episodeLength': 1400,
              'interval': {'startTime': 1320.0, 'endTime': 1390.0},
            },
            {
              'skipType': 'recap',
              'episodeLength': 1400,
              'interval': {'startTime': 20.0, 'endTime': 80.0},
            },
          ],
        }),
        200,
      );
    });
    final provider = AniSkipSegmentProvider(client: client);

    final markers = await provider.load(
      malId: 9253,
      episodeNumber: 1,
      episodeDuration: const Duration(seconds: 1420),
    );

    expect(requestedUri!.host, 'api.aniskip.com');
    expect(requestedUri!.path, '/v2/skip-times/9253/1');
    expect(requestedUri!.queryParameters['episodeLength'], '1420.000');
    expect(markers, hasLength(2));
    expect(markers.first.type, MediaSegmentType.intro);
    expect(markers.first.start, const Duration(milliseconds: 91429));
    expect(markers.first.end, const Duration(milliseconds: 182571));
    expect(markers.last.type, MediaSegmentType.credits);
    expect(markers.last.end, lessThanOrEqualTo(const Duration(seconds: 1420)));
  });

  test('returns no markers for invalid ids or unavailable API results', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('{"found":false,"results":[]}', 404);
    });
    final provider = AniSkipSegmentProvider(client: client);

    expect(
      await provider.load(
        malId: 0,
        episodeNumber: 1,
        episodeDuration: const Duration(minutes: 24),
      ),
      isEmpty,
    );
    expect(requests, 0);
    expect(
      await provider.load(
        malId: 9253,
        episodeNumber: 1,
        episodeDuration: const Duration(minutes: 24),
      ),
      isEmpty,
    );
  });
}
