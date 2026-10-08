import 'package:flutter/material.dart';
import 'package:omni_ai/features/dashboard/presentation/dashboard_page.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.preferencesStore});

  final UserPreferencesStore? preferencesStore;

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
      home: _AppStartupPage(preferencesStore: preferencesStore),
    );
  }
}

class _AppStartupPage extends StatefulWidget {
  const _AppStartupPage({required this.preferencesStore});

  final UserPreferencesStore? preferencesStore;

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
          return DashboardPage(preferences: preferences);
        }
        return SystemCorePage(preferencesStore: _preferencesStore);
      },
    );
  }
}
