import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_ai/features/favorites/data/favorite_item.dart';

/// Stores positive media feedback separately from the user's favorites list.
/// Likes teach local recommendations without automatically saving an item.
class MediaLikeRepository {
  MediaLikeRepository({this.store});

  static const storageKey = 'omni_ai.media_likes.v1';
  final SharedPreferencesAsync? store;
  SharedPreferencesAsync get _preferences => store ?? SharedPreferencesAsync();

  Future<List<FavoriteItem>> getAll() async {
    try {
      final encoded = await _preferences.getString(storageKey);
      if (encoded == null || encoded.isEmpty) return const <FavoriteItem>[];
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const <FavoriteItem>[];
      return List<FavoriteItem>.unmodifiable(
        decoded.map(FavoriteItem.fromJson).whereType<FavoriteItem>(),
      );
    } on Object {
      return const <FavoriteItem>[];
    }
  }

  Future<bool> contains(String id) async =>
      (await getAll()).any((item) => item.id == id);

  Future<bool> toggle(FavoriteItem item) async {
    final items = (await getAll()).toList();
    final existingIndex = items.indexWhere((saved) => saved.id == item.id);
    final isLiked = existingIndex < 0;
    if (isLiked) {
      items.add(item);
    } else {
      items.removeAt(existingIndex);
    }
    try {
      await _preferences.setString(
        storageKey,
        jsonEncode(items.map((saved) => saved.toJson()).toList()),
      );
    } on Object {
      // Feedback is optional; it must never block the media catalog.
    }
    return isLiked;
  }
}
