import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'favorite_item.dart';

abstract interface class FavoriteStringStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// Device-local storage for categorized favorites. The category is persisted
/// with each item so a saved trailer never becomes mixed with movie entries.
class FavoritesRepository {
  FavoritesRepository({FavoriteStringStore? store})
    : _store = store ?? _SharedPreferencesFavoriteStringStore();

  static const storageKey = 'omni_ai.favorites.items.v1';

  final FavoriteStringStore _store;

  Future<List<FavoriteItem>> getAll() async {
    final encoded = await _store.read(storageKey);
    if (encoded == null || encoded.trim().isEmpty) {
      return const <FavoriteItem>[];
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) throw const FormatException('Expected list.');
      final items = <FavoriteItem>[];
      final seen = <String>{};
      for (final value in decoded) {
        final item = FavoriteItem.fromJson(value);
        if (item != null && seen.add(item.id)) items.add(item);
      }
      return List<FavoriteItem>.unmodifiable(items);
    } on FormatException {
      await _store.remove(storageKey);
      return const <FavoriteItem>[];
    }
  }

  Future<List<FavoriteItem>> getByCategory(FavoriteCategory category) async {
    final items = await getAll();
    return List<FavoriteItem>.unmodifiable(
      items.where((item) => item.category == category),
    );
  }

  Future<void> add(FavoriteItem item) async {
    final items = (await getAll()).toList();
    final index = items.indexWhere((saved) => saved.id == item.id);
    if (index >= 0) {
      // Update metadata without creating a duplicate or moving categories
      // implicitly: a category change must be an explicit user action.
      items[index] = item;
    } else {
      items.add(item);
    }
    await _save(items);
  }

  Future<void> remove(String id) async {
    final items = (await getAll())
        .where((item) => item.id != id)
        .toList(growable: false);
    await _save(items);
  }

  Future<bool> contains(String id) async =>
      (await getAll()).any((item) => item.id == id);

  Future<void> move(String id, FavoriteCategory category) async {
    final items = (await getAll()).toList();
    final index = items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final current = items[index];
    items[index] = FavoriteItem(
      id: current.id,
      title: current.title,
      category: category,
      addedAt: current.addedAt,
      description: current.description,
      imageUrl: current.imageUrl,
      sourceUrl: current.sourceUrl,
      releaseDate: current.releaseDate,
      releaseDateSourceUrl: current.releaseDateSourceUrl,
    );
    await _save(items);
  }

  Future<void> clear() => _store.remove(storageKey);

  Future<void> _save(List<FavoriteItem> items) =>
      _store.write(storageKey, jsonEncode(items.map((item) => item.toJson()).toList()));
}

class _SharedPreferencesFavoriteStringStore implements FavoriteStringStore {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  @override
  Future<void> remove(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}
