import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/services/media_catalog_token_store.dart';
import 'package:omni_ai/features/settings/presentation/pages/media_catalog_settings_page.dart';

void main() {
  testWidgets('saves a catalog token and reports secure configuration', (
    tester,
  ) async {
    final store = _FakeMediaCatalogTokenStore();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MediaCatalogSettingsPage(tokenStore: store)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Токен не настроен — онлайн-поиск не работает'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('tmdb-token-field')),
      '  user-token  ',
    );
    await tester.tap(find.byKey(const ValueKey('save-tmdb-token')));
    await tester.pumpAndSettle();

    expect(store.token, 'user-token');
    expect(find.text('Токен настроен на этом устройстве'), findsOneWidget);
    expect(
      find.textContaining('Токен сохранён в защищённом хранилище'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('deletes a previously configured catalog token', (
    tester,
  ) async {
    final store = _FakeMediaCatalogTokenStore()..token = 'saved-token';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MediaCatalogSettingsPage(tokenStore: store)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Токен настроен на этом устройстве'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-tmdb-token')));
    await tester.pumpAndSettle();

    expect(store.token, isNull);
    expect(find.text('Токен не настроен — онлайн-поиск не работает'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeMediaCatalogTokenStore implements MediaCatalogTokenStore {
  String? token;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async {
    token = value.trim();
  }

  @override
  Future<void> deleteToken() async {
    token = null;
  }
}
