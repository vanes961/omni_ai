import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:omni_ai/features/media/services/media_segment_marker_store.dart';

/// Reads community-sourced anime opening and ending timestamps from AniSkip.
///
/// AniSkip requires a MyAnimeList ID and an absolute episode number. Callers
/// must not pass a TMDB ID as [malId].
class AniSkipSegmentProvider {
  AniSkipSegmentProvider({this.client});

  final http.Client? client;

  Future<List<MediaSegmentMarker>> load({
    required int malId,
    required int episodeNumber,
    required Duration episodeDuration,
  }) async {
    if (malId <= 0 || episodeNumber <= 0 || episodeDuration <= Duration.zero) {
      return const [];
    }

    final uri = Uri.https(
      'api.aniskip.com',
      '/v2/skip-times/$malId/$episodeNumber',
      {
        'types[]': ['op', 'ed'],
        'episodeLength': (episodeDuration.inMilliseconds / 1000)
            .toStringAsFixed(3),
      },
    );

    try {
      final response = await (client?.get(uri) ?? http.get(uri)).timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != 200) return const [];

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['found'] != true ||
          decoded['results'] is! List) {
        return const [];
      }

      final markers = <MediaSegmentMarker>[];
      for (final result in decoded['results'] as List) {
        if (result is! Map<String, dynamic>) continue;
        final interval = result['interval'];
        final type = result['skipType'];
        final sourceDuration = result['episodeLength'];
        if (interval is! Map<String, dynamic> ||
            sourceDuration is! num ||
            sourceDuration <= 0) {
          continue;
        }

        final rawStart = interval['startTime'];
        final rawEnd = interval['endTime'];
        if (rawStart is! num || rawEnd is! num) continue;

        final markerType = switch (type) {
          'op' => MediaSegmentType.intro,
          'ed' => MediaSegmentType.credits,
          _ => null,
        };
        if (markerType == null) continue;

        // Different encodes often have slightly different runtimes. Scale
        // source timestamps to the actual duration of the playing file.
        final scale =
            episodeDuration.inMilliseconds / (sourceDuration.toDouble() * 1000);
        final start = Duration(
          milliseconds: (rawStart.toDouble() * 1000 * scale).round(),
        );
        final end = Duration(
          milliseconds: (rawEnd.toDouble() * 1000 * scale).round(),
        );
        final marker = MediaSegmentMarker(
          type: markerType,
          start: start,
          end: end,
        );
        if (marker.isValid &&
            marker.end <= episodeDuration &&
            marker.start < episodeDuration) {
          markers.add(marker);
        }
      }

      markers.sort((a, b) => a.start.compareTo(b.start));
      return markers;
    } on Object {
      // AniSkip is an optional source; network/API errors must not break
      // playback or prevent locally saved markers from working.
      return const [];
    }
  }
}
