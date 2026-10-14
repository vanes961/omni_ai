import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/presentation/manga_reader_progress_overlay.dart';

void main() {
  Widget buildReaderBadge({
    String chapter = '24',
    int currentPage = 18,
    int totalPages = 42,
  }) => MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(color: Colors.black),
          ),
          MangaReaderProgressOverlay(
            chapterLabel: chapter,
            currentPage: currentPage,
            totalPages: totalPages,
          ),
        ],
      ),
    ),
  );

  testWidgets('starts as a compact chapter badge', (tester) async {
    await tester.pumpWidget(buildReaderBadge());

    expect(find.text('Глава 24'), findsOneWidget);
    expect(find.text('18/42'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('tap reveals page count and chapter progress', (tester) async {
    await tester.pumpWidget(buildReaderBadge());

    await tester.tap(find.byKey(const ValueKey('manga-reader-progress-toggle')));
    await tester.pump();

    expect(find.text('Глава 24'), findsOneWidget);
    expect(find.text('18/42'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      ).value,
      closeTo(18 / 42, 0.001),
    );
  });

  testWidgets('handles missing page totals without division by zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildReaderBadge(chapter: '', currentPage: 0, totalPages: 0),
    );

    await tester.tap(find.byKey(const ValueKey('manga-reader-progress-toggle')));
    await tester.pump();

    expect(find.text('Чтение'), findsOneWidget);
    expect(find.text('0/0'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('clamps an out-of-range page to the chapter bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildReaderBadge(currentPage: 99, totalPages: 12),
    );

    await tester.tap(find.byKey(const ValueKey('manga-reader-progress-toggle')));
    await tester.pump();

    expect(find.text('12/12'), findsOneWidget);
  });
}
