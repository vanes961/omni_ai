import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/presentation/manga_reader_progress_overlay.dart';

const testChapters = [
  MangaReaderChapterOption(id: 'ch-22', label: '22', title: 'Начало'),
  MangaReaderChapterOption(id: 'ch-23', label: '23'),
  MangaReaderChapterOption(id: 'ch-24', label: '24', title: 'Текущая глава'),
  MangaReaderChapterOption(id: 'ch-25', label: '25'),
];

void main() {
  Widget buildReaderBadge({
    String chapter = '24',
    int currentPage = 18,
    int totalPages = 42,
    List<MangaReaderChapterOption> chapters = testChapters,
    ValueChanged<MangaReaderChapterOption>? onChapterSelected,
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
            chapters: chapters,
            onChapterSelected: onChapterSelected,
          ),
        ],
      ),
    ),
  );

  testWidgets('shows a compact chapter badge and progress', (tester) async {
    await tester.pumpWidget(buildReaderBadge());

    expect(find.text('Гл. 24'), findsOneWidget);
    expect(find.text('18/42'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('chapter tap opens the complete chapter list', (tester) async {
    await tester.pumpWidget(buildReaderBadge());

    await tester.tap(find.byKey(const ValueKey('manga-reader-chapter-picker')));
    await tester.pumpAndSettle();

    expect(find.text('Все главы'), findsOneWidget);
    expect(find.text('Глава 22'), findsOneWidget);
    expect(find.text('Глава 23'), findsOneWidget);
    expect(find.text('Глава 24'), findsOneWidget);
    expect(find.text('Глава 25'), findsOneWidget);
    expect(find.text('Текущая глава'), findsOneWidget);
  });

  testWidgets('selecting a chapter returns it to the reader', (tester) async {
    MangaReaderChapterOption? selected;
    await tester.pumpWidget(
      buildReaderBadge(onChapterSelected: (chapter) => selected = chapter),
    );

    await tester.tap(find.byKey(const ValueKey('manga-reader-chapter-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('manga-chapter-ch-25')));
    await tester.pumpAndSettle();

    expect(selected?.id, 'ch-25');
    expect(selected?.label, '25');
  });

  testWidgets('handles missing page totals without division by zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildReaderBadge(
        chapter: '',
        currentPage: 0,
        totalPages: 0,
        chapters: const [],
      ),
    );

    expect(find.text('Чтение'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('clamps an out-of-range page to the chapter bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildReaderBadge(currentPage: 99, totalPages: 12, chapters: const []),
    );

    expect(find.text('12/12'), findsOneWidget);
  });
}
