import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/di/app_dependencies.dart';
import 'package:omni_ai/features/run_history/models/process_run_record.dart';
import 'package:omni_ai/features/run_history/repositories/run_history_repository.dart';
import 'package:omni_ai/features/ai_chat/presentation/floating_ai_companion.dart';

class _TestAIProvider implements AIProvider {
  @override
  String get id => 'test';

  @override
  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  }) {
    throw UnimplementedError('The companion widget tests do not send requests.');
  }
}

class _TestRunHistoryRepository implements RunHistoryRepository {
  @override
  Stream<List<ProcessRunRecord>> watch() => const Stream.empty();

  @override
  Future<List<ProcessRunRecord>> getAll() async => const [];

  @override
  Future<void> save(ProcessRunRecord record) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> dispose() async {}
}

AppDependencies _createDependencies() => AppDependencies(
  localAIProvider: _TestAIProvider(),
  runHistoryRepository: _TestRunHistoryRepository(),
);

Future<void> _disposeDependencies(
  WidgetTester tester,
  AppDependencies dependencies,
) async {
  // Unmount the chat first so its async initialization cannot overlap teardown.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.runAsync(dependencies.dispose);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('opens chat over the current screen and can be collapsed', (
    tester,
  ) async {
    final dependencies = _createDependencies();

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
    await _disposeDependencies(tester, dependencies);
  });

  testWidgets('can hide and restore the floating companion', (tester) async {
    final dependencies = _createDependencies();

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
    await _disposeDependencies(tester, dependencies);
  });

  testWidgets('can drag the companion without removing the current screen', (
    tester,
  ) async {
    final dependencies = _createDependencies();

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
    await _disposeDependencies(tester, dependencies);
  });
}

