import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/services/media_headers.dart';
import 'package:omni_ai/features/telegram/presentation/widgets/telegram_post_card.dart';

import 'telegram_parser_service_test.dart' show createTestPost;

void main() {
  testWidgets('shows post media and opens its source URL', (tester) async {
    Uri? openedUri;
    final post = createTestPost();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TelegramPostCard(
            post: post,
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
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(
      image.httpHeaders,
      MediaHeaders.getHeaders(post.mediaUrl!),
    );
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('source-post-test')));
    await tester.pumpAndSettle();

    expect(openedUri, Uri.parse('https://t.me/life_free_hub/145'));
  });
}
