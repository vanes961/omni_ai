import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/core/ai_engine/local/local_model_storage.dart';
import 'package:omni_ai/features/settings/presentation/pages/local_model_settings_page.dart';

void main() {
  testWidgets(
    'allows verifying and restoring an already installed local model',
    (tester) async {
      final storage = _InstalledModelStorage();

      await tester.pumpWidget(
        MaterialApp(home: LocalModelSettingsPage(storage: storage)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Файл модели найден'), findsOneWidget);
      expect(
        find.text('ПРОВЕРИТЬ / ВОССТАНОВИТЬ МОДЕЛЬ'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('local-model-download-button')),
      );
      await tester.pumpAndSettle();

      expect(storage.installCalls, 1);
      expect(find.textContaining('Модель проверена.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      storage.dispose();
    },
  );
}

class _InstalledModelStorage extends LocalModelStorage {
  _InstalledModelStorage()
    : super(supportDirectoryProvider: () async => Directory.systemTemp);

  int installCalls = 0;

  @override
  Future<bool> isDownloaded(LocalModelSpec model) async => true;

  @override
  Future<File> installBundled(LocalModelSpec model) async {
    installCalls++;
    return File('${Directory.systemTemp.path}/${model.fileName}');
  }
}
