import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/favorites/data/favorite_item.dart';
import 'package:omni_ai/features/favorites/data/favorites_repository.dart';
import 'package:omni_ai/features/media/presentation/manga_catalog_page.dart';
import 'package:omni_ai/features/media/services/manga_catalog_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('catalog error offers retry and recovers when MangaDex returns', (
    tester,
  ) async {
    var requests = 0;
    final favoritesStore = _MemoryFavoriteStore();
    final favorites = FavoritesRepository(store: favoritesStore);
    final service = MangaCatalogService(
      client: MockClient((_) async {
        requests++;
        if (requests == 1) return http.Response('temporarily unavailable', 503);
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 'berserk-id',
                'attributes': {
                  'title': {'en': 'Berserk'},
                  'description': {'ru': 'Описание'},
                  'status': 'completed',
                },
                'relationships': [],
              },
            ],
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MangaCatalogPage(
          catalogService: service,
          favoritesRepository: favorites,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Berserk');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Не удалось загрузить каталог'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('manga-catalog-retry')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('manga-catalog-berserk-id')),
      findsNothing,
    );
    expect(requests, 1);

    await tester.tap(find.byKey(const ValueKey('manga-catalog-retry')));
    await tester.pumpAndSettle();

    expect(requests, 2);
    expect(
      find.byKey(const ValueKey('manga-catalog-berserk-id')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('manga-catalog-berserk-id')),
        matching: find.text('Berserk'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Не удалось загрузить каталог'), findsNothing);

    final favoriteButton = find.byKey(
      const ValueKey('manga-favorite-berserk-id'),
    );
    expect(favoriteButton, findsOneWidget);
    await tester.tap(favoriteButton);
    await tester.pumpAndSettle();
    final saved = (await favorites.getByCategory(
      FavoriteCategory.manga,
    )).single;
    expect(saved.id, 'mangadex:berserk-id');
    expect(saved.title, 'Berserk');
    expect(saved.description, 'Описание');
    expect(saved.sourceUrl, 'https://mangadex.org/title/berserk-id');
    expect(saved.category, FavoriteCategory.manga);

    await tester.tap(favoriteButton);
    await tester.pumpAndSettle();
    expect(await favorites.getAll(), isEmpty);
    service.close();
  });
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
