import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/core/di/app_dependencies.dart';
import 'package:omni_ai/features/dashboard/presentation/dashboard_page.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.preferencesStore, this.dependencies});

  final UserPreferencesStore? preferencesStore;
  final AppDependencies? dependencies;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final bool _ownsDependencies = widget.dependencies == null;
  late final AppDependencies _dependencies =
      widget.dependencies ?? AppDependencies();

  @override
  void dispose() {
    if (_ownsDependencies) unawaited(_dependencies.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OMNI_AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: SystemCorePalette.background,
        colorScheme: const ColorScheme.dark(
          primary: SystemCorePalette.green,
          secondary: SystemCorePalette.mint,
          surface: SystemCorePalette.panel,
          error: SystemCorePalette.red,
        ),
        fontFamily: 'monospace',
        useMaterial3: true,
        splashFactory: InkSparkle.splashFactory,
        dividerColor: SystemCorePalette.border,
        cardTheme: CardThemeData(
          color: SystemCorePalette.panel,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: SystemCorePalette.border),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: SystemCorePalette.panel,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          hintStyle: const TextStyle(color: SystemCorePalette.muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: SystemCorePalette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: SystemCorePalette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: SystemCorePalette.green,
              width: 1.5,
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: SystemCorePalette.green,
            foregroundColor: SystemCorePalette.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          ),
        ),
      ),
      home: _AppStartupPage(
        preferencesStore: widget.preferencesStore,
        dependencies: _dependencies,
      ),
    );
  }
}

class _AppStartupPage extends StatefulWidget {
  const _AppStartupPage({
    required this.preferencesStore,
    required this.dependencies,
  });

  final UserPreferencesStore? preferencesStore;
  final AppDependencies dependencies;

  @override
  State<_AppStartupPage> createState() => _AppStartupPageState();
}

class _AppStartupPageState extends State<_AppStartupPage> {
  late final UserPreferencesStore _preferencesStore;
  late Future<UserPreferences?> _preferences;

  @override
  void initState() {
    super.initState();
    _preferencesStore =
        widget.preferencesStore ?? SharedPreferencesUserPreferencesStore();
    _preferences = _preferencesStore.load();
  }

  void _retryLoading() {
    setState(() => _preferences = _preferencesStore.load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserPreferences?>(
      future: _preferences,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: SystemCorePalette.green),
            ),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('НЕ УДАЛОСЬ ЗАГРУЗИТЬ ПРОФИЛЬ'),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _retryLoading,
                    child: const Text('ПОВТОРИТЬ'),
                  ),
                ],
              ),
            ),
          );
        }

        final preferences = snapshot.data;
        if (preferences != null) {
          // Remove legacy onboarding selections that used to pin demo channels,
          // fixed titles and voiceover providers into the first-run experience.
          if (preferences.categories.isNotEmpty ||
              preferences.favoriteTitles.isNotEmpty ||
              preferences.voiceDubbing.isNotEmpty ||
              preferences.tgChannels.isNotEmpty) {
            preferences
              ..categories = <String>[]
              ..favoriteTitles = <String>[]
              ..voiceDubbing = <String>[]
              ..tgChannels = <String>[];
            unawaited(_preferencesStore.save(preferences));
          }
          return DashboardPage(
            preferences: preferences,
            preferencesStore: _preferencesStore,
            dependencies: widget.dependencies,
          );
        }
        final cleanPreferences = UserPreferences();
        return DashboardPage(
          preferences: cleanPreferences,
          preferencesStore: _preferencesStore,
          dependencies: widget.dependencies,
        );
      },
    );
  }
}
