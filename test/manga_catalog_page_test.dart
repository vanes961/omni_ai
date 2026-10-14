import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/features/media/presentation/manga_catalog_page.dart';
import 'package:omni_ai/features/media/services/manga_catalog_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('catalog error offers retry and recovers when MangaDex returns', (
    tester,
  ) async {
    var requests = 0;
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
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: MangaCatalogPage(catalogService: service)),
    );
    await tester.enterText(find.byType(TextField), 'Berserk');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.textContaining('Не удалось загрузить каталог'), findsOneWidget);
    expect(find.byKey(const ValueKey('manga-catalog-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('manga-catalog-berserk-id')), findsNothing);
    expect(requests, 1);

    await tester.tap(find.byKey(const ValueKey('manga-catalog-retry')));
    await tester.pumpAndSettle();

    expect(requests, 2);
    expect(find.byKey(const ValueKey('manga-catalog-berserk-id')), findsOneWidget);
    expect(find.text('Berserk'), findsOneWidget);
    expect(find.textContaining('Не удалось загрузить каталог'), findsNothing);
    service.close();
  });
}
