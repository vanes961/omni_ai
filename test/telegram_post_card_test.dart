import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/telegram/presentation/widgets/telegram_post_card.dart';

import 'telegram_parser_service_test.dart' show createTestPost;

void main() {
  testWidgets('shows post media and opens its source URL', (tester) async {
    Uri? openedUri;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TelegramPostCard(
            post: createTestPost(),
            sourceLauncher: (uri) async {
              openedUri = uri;
              return true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Life Free Hub'), findsOneWidget);
    expect(find.text('Test post with image'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('source-post-test')));
    await tester.pumpAndSettle();

    expect(openedUri, Uri.parse('https://t.me/life_free_hub/145'));
  });
}
