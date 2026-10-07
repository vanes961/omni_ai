import 'package:flutter/material.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OMNI_AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: SystemCorePalette.background,
        colorScheme: const ColorScheme.dark(
          primary: SystemCorePalette.red,
          secondary: SystemCorePalette.green,
          surface: SystemCorePalette.panel,
        ),
        fontFamily: 'monospace',
        useMaterial3: true,
      ),
      home: const SystemCorePage(),
    );
  }
}
