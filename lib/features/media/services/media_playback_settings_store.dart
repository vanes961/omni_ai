import 'package:shared_preferences/shared_preferences.dart';

/// Persists per-title voiceover choice and global voiceover feedback.
abstract interface class MediaPlaybackSettingsStore {
  Future<String?> loadVoiceover(String mediaId);
  Future<void> saveVoiceover(String mediaId, String voiceover);
  Future<String?> loadQuality(String mediaId);
  Future<void> saveQuality(String mediaId, String quality);
  Future<Set<String>> loadLikedVoiceovers();
  Future<bool> toggleVoiceoverLike(String voiceover);
}

class SharedPreferencesMediaPlaybackSettingsStore
    implements MediaPlaybackSettingsStore {
  SharedPreferencesMediaPlaybackSettingsStore({this.store});

  static const _likesKey = 'omni_ai.media_voiceover_likes.v1';
  final SharedPreferencesAsync? store;

  SharedPreferencesAsync get _preferences => store ?? SharedPreferencesAsync();

  String _voiceoverKey(String mediaId) => 'omni_ai.media_voiceover.v1.$mediaId';

  String _qualityKey(String mediaId) => 'omni_ai.media_quality.v1.$mediaId';

  @override
  Future<String?> loadVoiceover(String mediaId) async {
    try {
      final value = await _preferences.getString(_voiceoverKey(mediaId));
      return value?.trim().isNotEmpty == true ? value : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveVoiceover(String mediaId, String voiceover) async {
    try {
      await _preferences.setString(_voiceoverKey(mediaId), voiceover);
    } on Object {
      // A preference failure must not interrupt playback.
    }
  }

  @override
  Future<String?> loadQuality(String mediaId) async {
    try {
      final value = await _preferences.getString(_qualityKey(mediaId));
      return value?.trim().isNotEmpty == true ? value : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveQuality(String mediaId, String quality) async {
    try {
      await _preferences.setString(_qualityKey(mediaId), quality);
    } on Object {
      // A preference failure must not interrupt playback.
    }
  }

  @override
  Future<Set<String>> loadLikedVoiceovers() async {
    try {
      final values = await _preferences.getStringList(_likesKey);
      return values
              ?.map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet() ??
          <String>{};
    } on Object {
      return <String>{};
    }
  }

  @override
  Future<bool> toggleVoiceoverLike(String voiceover) async {
    final normalized = voiceover.trim();
    if (normalized.isEmpty) return false;
    final liked = await loadLikedVoiceovers();
    final nowLiked = !liked.remove(normalized);
    if (nowLiked) liked.add(normalized);
    try {
      await _preferences.setStringList(_likesKey, liked.toList()..sort());
    } on Object {
      // Voiceover feedback is optional and must never block playback.
    }
    return nowLiked;
  }
}
