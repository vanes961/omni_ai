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

class _AppStartupPageState extends State<_AppStartupPage>
    with SingleTickerProviderStateMixin {
  late final UserPreferencesStore _preferencesStore;
  late Future<UserPreferences?> _preferences;

  late final AnimationController _progress;
  bool _splashElapsed = false;

  @override
  void initState() {
    super.initState();
    _preferencesStore =
        widget.preferencesStore ?? SharedPreferencesUserPreferencesStore();
    _preferences = _preferencesStore.load();
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..forward();
    _progress.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _splashElapsed = true);
      }
    });
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _retryLoading() {
    setState(() {
      _preferences = _preferencesStore.load();
      _splashElapsed = false;
    });
    _progress.reset();
    _progress.forward();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserPreferences?>(
      future: _preferences,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !_splashElapsed) {
          return _OmniLoadingScreen(progress: _progress);
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


class _OmniLoadingScreen extends StatelessWidget {
  const _OmniLoadingScreen({required this.progress});

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070B),
      body: AnimatedBuilder(
        animation: progress,
        builder: (context, _) {
          final amount = progress.value.clamp(0.0, 1.0);
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.15),
                radius: 1.2,
                colors: [Color(0xFF17313A), Color(0xFF080B12), Color(0xFF030407)],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 30),
                child: Column(
                  children: [
                    const Spacer(flex: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                      decoration: BoxDecoration(
                        color: const Color(0xB5081017),
                        border: Border.all(color: const Color(0xFF31F5B0)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF22F0B0).withValues(alpha: 0.2),
                            blurRadius: 28,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            'OMNI',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 44,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 8,
                              shadows: [
                                Shadow(
                                  color: const Color(0xFF2DF8B1).withValues(alpha: 0.8),
                                  blurRadius: 18,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'AI  //  INTELLIGENCE HUB',
                            style: TextStyle(
                              color: Color(0xFF4BFFD0),
                              fontSize: 10,
                              letterSpacing: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(flex: 3),
                    const Text(
                      'СИСТЕМА ИНИЦИАЛИЗИРУЕТСЯ',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 2),
                    ),
                    const Spacer(flex: 2),
                    Row(
                      children: [
                        const Text('ЗАГРУЗКА...', style: TextStyle(color: Color(0xFF57FFD0), fontSize: 11, letterSpacing: 1.5)),
                        const Spacer(),
                        Text(
                          '${(amount * 100).round()}%',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 7,
                        child: Stack(
                          children: [
                            const ColoredBox(color: Color(0xFF18252B), child: SizedBox.expand()),
                            FractionallySizedBox(
                              widthFactor: amount,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0xFF7B2CFF), Color(0xFF20FFD0), Color(0xFFB8FF49)],
                                  ),
                                ),
                                child: SizedBox.expand(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 13),
                    const Text(
                      'ПОДГОТОВКА МОДУЛЕЙ  •  ЗАГРУЗКА ПРОФИЛЯ',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF8797A2), fontSize: 9, letterSpacing: 1),
                    ),
                    const SizedBox(height: 12),
                    const Text('Версия 1.0.0', style: TextStyle(color: Color(0xFF53616C), fontSize: 10)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
