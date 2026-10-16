import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:omni_ai/core/di/app_dependencies.dart';
import 'package:omni_ai/features/ai_chat/presentation/floating_ai_companion.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('opens chat over the current screen and can be collapsed', (
    tester,
  ) async {
    final dependencies = AppDependencies();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Center(child: Text('Текущий экран')),
              FloatingAICompanion(dependencies: dependencies),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Текущий экран'), findsOneWidget);
    expect(find.text('OMNI AI · помощник'), findsNothing);

    await tester.tap(find.byIcon(Icons.smart_toy_rounded).first);
    await tester.pump();

    expect(find.text('Текущий экран'), findsOneWidget);
    expect(find.text('OMNI AI · помощник'), findsOneWidget);
    expect(find.byTooltip('Свернуть'), findsOneWidget);

    await tester.tap(find.byTooltip('Свернуть'));
    await tester.pump();

    expect(find.text('OMNI AI · помощник'), findsNothing);
    expect(find.text('Текущий экран'), findsOneWidget);
  });

  testWidgets('keeps the open chat window floating and width-constrained', (
    tester,
  ) async {
    final dependencies = AppDependencies();
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Center(child: Text('Текущий экран')),
              FloatingAICompanion(dependencies: dependencies),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.smart_toy_rounded).first);
    await tester.pump();

    final panel = find.byWidgetPredicate(
      (widget) =>
          widget is Material &&
          widget.borderRadius == BorderRadius.circular(22),
    );
    expect(panel, findsOneWidget);
    final panelRect = tester.getRect(panel);
    expect(panelRect.width, lessThanOrEqualTo(560));
    expect(panelRect.height, lessThan(900));
    expect(panelRect.bottom, lessThan(900));
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the compact header in the floating chat', (tester) async {
    final dependencies = AppDependencies();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Center(child: Text('Текущий экран')),
              FloatingAICompanion(dependencies: dependencies),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.smart_toy_rounded).first);
    await tester.pump();

    expect(find.text('OMNI AI · помощник'), findsOneWidget);
    expect(find.text('ЛИЧНЫЙ ПОМОЩНИК'), findsNothing);
    expect(find.byTooltip('Долговременная память'), findsOneWidget);
    await tester.tap(find.byTooltip('Долговременная память'));
    await tester.pumpAndSettle();
    expect(find.text('Долговременная память'), findsOneWidget);
    expect(find.text('Что запомнить?'), findsOneWidget);
    await tester.tap(find.text('Закрыть'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('can hide and restore the floating companion', (tester) async {
    final dependencies = AppDependencies();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Center(child: Text('Текущий экран')),
              FloatingAICompanion(dependencies: dependencies),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.smart_toy_rounded).first);
    await tester.pump();
    await tester.tap(find.byTooltip('Скрыть помощника'));
    await tester.pump();

    expect(find.text('OMNI AI · помощник'), findsNothing);
    expect(find.byTooltip('Показать AI-компаньона'), findsOneWidget);

    await tester.tap(find.byTooltip('Показать AI-компаньона'));
    await tester.pump();

    expect(find.byTooltip('Показать AI-компаньона'), findsNothing);
    expect(find.byIcon(Icons.smart_toy_rounded), findsOneWidget);
    expect(find.text('Текущий экран'), findsOneWidget);
  });

  testWidgets('can drag the companion without removing the current screen', (
    tester,
  ) async {
    final dependencies = AppDependencies();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Center(child: Text('Текущий экран')),
              FloatingAICompanion(dependencies: dependencies),
            ],
          ),
        ),
      ),
    );

    final robot = find.byIcon(Icons.smart_toy_rounded).first;
    final before = tester.getCenter(robot);
    await tester.drag(robot, const Offset(-70, -50));
    await tester.pump();

    final after = tester.getCenter(find.byIcon(Icons.smart_toy_rounded).first);
    expect(after.dx, lessThan(before.dx));
    expect(after.dy, lessThan(before.dy));
    expect(find.text('Текущий экран'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

