import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/favorites/data/favorite_item.dart';
import 'package:omni_ai/features/favorites/data/favorites_repository.dart';

void main() {
  late _MemoryFavoriteStore store;
  late FavoritesRepository repository;

  setUp(() {
    store = _MemoryFavoriteStore();
    repository = FavoritesRepository(store: store);
  });

  test('stores and retrieves favorites in separate categories', () async {
    await repository.add(_item('movie-1', FavoriteCategory.movie));
    await repository.add(_item('anime-1', FavoriteCategory.anime));
    await repository.add(_item('trailer-1', FavoriteCategory.trailer));

    expect(
      (await repository.getByCategory(FavoriteCategory.movie))
          .map((item) => item.id),
      ['movie-1'],
    );
    expect(
      (await repository.getByCategory(FavoriteCategory.anime))
          .map((item) => item.id),
      ['anime-1'],
    );
    expect(
      (await repository.getByCategory(FavoriteCategory.trailer))
          .map((item) => item.id),
      ['trailer-1'],
    );
  });

  test('adding the same id does not create a duplicate', () async {
    await repository.add(_item('same-id', FavoriteCategory.movie));
    await repository.add(
      _item('same-id', FavoriteCategory.movie, title: 'Updated title'),
    );

    final all = await repository.getAll();
    expect(all, hasLength(1));
    expect(all.single.title, 'Updated title');
  });

  test('duplicate add cannot silently move an item to another category', () async {
    await repository.add(_item('same-id', FavoriteCategory.movie));
    await repository.add(_item('same-id', FavoriteCategory.trailer));

    expect(
      (await repository.getByCategory(FavoriteCategory.movie)).single.id,
      'same-id',
    );
    expect(await repository.getByCategory(FavoriteCategory.trailer), isEmpty);
  });

  test('removes an item and reports membership correctly', () async {
    await repository.add(_item('remove-me', FavoriteCategory.manga));

    expect(await repository.contains('remove-me'), isTrue);
    await repository.remove('remove-me');

    expect(await repository.contains('remove-me'), isFalse);
    expect(await repository.getAll(), isEmpty);
  });

  test('can explicitly move an item to another category', () async {
    await repository.add(_item('series-1', FavoriteCategory.series));

    await repository.move('series-1', FavoriteCategory.anime);

    expect(await repository.getByCategory(FavoriteCategory.series), isEmpty);
    expect(
      (await repository.getByCategory(FavoriteCategory.anime)).single.id,
      'series-1',
    );
  });

  test('round-trips trailer release date and source links', () async {
    final releaseDate = DateTime.utc(2027, 4, 12);
    await repository.add(
      FavoriteItem(
        id: 'trailer-1',
        title: 'Example trailer',
        category: FavoriteCategory.trailer,
        addedAt: DateTime.utc(2026, 10, 10),
        sourceUrl: 'https://example.com/trailer',
        releaseDate: releaseDate,
        releaseDateSourceUrl: 'https://example.com/release-date',
      ),
    );

    final restored = (await repository.getByCategory(
      FavoriteCategory.trailer,
    )).single;
    expect(restored.releaseDate, releaseDate);
    expect(restored.sourceUrl, 'https://example.com/trailer');
    expect(restored.releaseDateSourceUrl, 'https://example.com/release-date');
  });

  test('ignores unsafe persisted URLs', () {
    final item = FavoriteItem.fromJson({
      ..._item('unsafe', FavoriteCategory.movie).toJson(),
      'sourceUrl': 'javascript:alert(1)',
      'imageUrl': 'file:///private/image.png',
    });

    expect(item, isNotNull);
    expect(item!.sourceUrl, isNull);
    expect(item.imageUrl, isNull);
  });
}

FavoriteItem _item(
  String id,
  FavoriteCategory category, {
  String? title,
}) {
  return FavoriteItem(
    id: id,
    title: title ?? id,
    category: category,
    addedAt: DateTime.utc(2026, 10, 10),
  );
}

class _MemoryFavoriteStore implements FavoriteStringStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
