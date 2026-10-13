import 'package:shared_preferences/shared_preferences.dart';

abstract interface class MediaResumePositionStore {
  Future<Duration?> load(String mediaId, int episodeIndex);

  Future<void> save(
    String mediaId,
    int episodeIndex,
    Duration position,
    Duration duration,
  );

  Future<void> clear(String mediaId, int episodeIndex);

  Future<Set<int>> loadWatchedEpisodes(String mediaId);

  Future<void> markEpisodeWatched(String mediaId, int episodeIndex);
}

class SharedPreferencesMediaResumePositionStore
    implements MediaResumePositionStore {
  SharedPreferencesMediaResumePositionStore({SharedPreferencesAsync? store})
    : _store = store ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _store;

  String _key(String mediaId, int episodeIndex) =>
      'omni_ai.media_resume.v1.$mediaId.$episodeIndex';

  @override
  Future<Duration?> load(String mediaId, int episodeIndex) async {
    try {
      final milliseconds = await _store.getInt(_key(mediaId, episodeIndex));
      if (milliseconds == null || milliseconds <= 0) return null;
      return Duration(milliseconds: milliseconds);
    } on Object {
      // Playback should remain usable if local progress storage is unavailable.
      return null;
    }
  }

  @override
  Future<void> save(
    String mediaId,
    int episodeIndex,
    Duration position,
    Duration duration,
  ) async {
    final remaining = duration - position;
    if (position < const Duration(seconds: 10)) return;
    if (duration > Duration.zero && remaining <= const Duration(seconds: 15)) {
      await clear(mediaId, episodeIndex);
      await markEpisodeWatched(mediaId, episodeIndex);
      return;
    }
    try {
      await _store.setInt(_key(mediaId, episodeIndex), position.inMilliseconds);
    } on Object {
      // A storage error must not interrupt playback.
    }
  }

  @override
  Future<Set<int>> loadWatchedEpisodes(String mediaId) async {
    try {
      final values = await _store.getStringList(_watchedKey(mediaId));
      return values?.map(int.tryParse).whereType<int>().toSet() ?? <int>{};
    } on Object {
      return <int>{};
    }
  }

  @override
  Future<void> markEpisodeWatched(String mediaId, int episodeIndex) async {
    try {
      final watched = await loadWatchedEpisodes(mediaId);
      if (watched.add(episodeIndex)) {
        await _store.setStringList(
          _watchedKey(mediaId),
          watched.map((index) => index.toString()).toList(),
        );
      }
    } on Object {
      // History must never interrupt playback.
    }
  }

  String _watchedKey(String mediaId) =>
      'omni_ai.media_watched_episodes.v1.$mediaId';

  @override
  Future<void> clear(String mediaId, int episodeIndex) async {
    try {
      await _store.remove(_key(mediaId, episodeIndex));
    } on Object {
      // A storage error must not interrupt playback.
    }
  }
}
