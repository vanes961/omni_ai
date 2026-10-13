import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum MediaSegmentType { intro, credits }

class MediaSegmentMarker {
  const MediaSegmentMarker({
    required this.type,
    required this.start,
    required this.end,
  });

  final MediaSegmentType type;
  final Duration start;
  final Duration end;

  bool get isValid => start >= Duration.zero && end > start;

  Map<String, Object> toJson() => {
    'type': type.name,
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
  };

  static MediaSegmentMarker? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final typeName = value['type'];
    final startMs = value['startMs'];
    final endMs = value['endMs'];
    if (typeName is! String || startMs is! int || endMs is! int) {
      return null;
    }
    final type = MediaSegmentType.values.where((item) => item.name == typeName);
    if (type.isEmpty) return null;
    final marker = MediaSegmentMarker(
      type: type.first,
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
    );
    return marker.isValid ? marker : null;
  }
}

abstract interface class MediaSegmentMarkerStore {
  Future<List<MediaSegmentMarker>> load(String mediaId, int episodeIndex);

  Future<void> save(
    String mediaId,
    int episodeIndex,
    List<MediaSegmentMarker> markers,
  );
}

class SharedPreferencesMediaSegmentMarkerStore
    implements MediaSegmentMarkerStore {
  SharedPreferencesMediaSegmentMarkerStore({SharedPreferencesAsync? store})
    : _store = store;

  final SharedPreferencesAsync? _store;

  SharedPreferencesAsync get _preferences => _store ?? SharedPreferencesAsync();

  String _key(String mediaId, int episodeIndex) =>
      'omni_ai.media_segments.v1.$mediaId.$episodeIndex';

  @override
  Future<List<MediaSegmentMarker>> load(
    String mediaId,
    int episodeIndex,
  ) async {
    try {
      final raw = await _preferences.getString(_key(mediaId, episodeIndex));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(MediaSegmentMarker.fromJson)
          .whereType<MediaSegmentMarker>()
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> save(
    String mediaId,
    int episodeIndex,
    List<MediaSegmentMarker> markers,
  ) async {
    final valid = markers.where((marker) => marker.isValid).toList();
    try {
      await _preferences.setString(
        _key(mediaId, episodeIndex),
        jsonEncode(valid.map((marker) => marker.toJson()).toList()),
      );
    } on Object {
      // Marker storage must never interrupt playback.
    }
  }
}
