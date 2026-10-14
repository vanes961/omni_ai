import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/core/ai_engine/local/local_model_storage.dart';
import 'package:omni_ai/core/di/ai_dependencies.dart';
import 'package:omni_ai/core/di/app_dependencies.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:omni_ai/features/media/services/franchise_chronology_coordinator.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/media/services/openrouter_franchise_chronology_researcher.dart';
import 'package:omni_ai/features/media/services/shared_preferences_franchise_chronology_cache.dart';
import 'package:omni_ai/features/ai_chat/presentation/ai_chat_page.dart';
import 'package:omni_ai/features/media/presentation/media_page.dart';
import 'package:omni_ai/features/favorites/presentation/favorites_page.dart';
import 'package:omni_ai/features/news/presentation/news_center_page.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/settings/presentation/pages/local_model_settings_page.dart';
import 'package:omni_ai/features/settings/presentation/pages/media_catalog_settings_page.dart';
import 'package:omni_ai/features/settings/presentation/pages/network_settings_page.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    required this.preferences,
    this.preferencesStore,
    this.dependencies,
    this.initialTab = 0,
    super.key,
  });

  final UserPreferences preferences;
  final UserPreferencesStore? preferencesStore;
  final AppDependencies? dependencies;
  final int initialTab;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late int _selectedTab;

  int _selectedSettingsTab = 0;
  late final bool _ownsDependencies;
  late final LocalModelStorage _localModelStorage;
  late final AIDependencies _aiDependencies;
  late final AppDependencies _chatDependencies;
  late final UserPreferencesStore _preferencesStore;
  late final FranchiseChronologyResolver _franchiseChronologyResolver;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab.clamp(0, 4).toInt();
    final dependencies = widget.dependencies;
    _ownsDependencies = dependencies == null;
    if (dependencies == null) {
      _chatDependencies = AppDependencies();
      _localModelStorage = _chatDependencies.localModelStorage;
      _aiDependencies = _chatDependencies.ai;
    } else {
      _localModelStorage = dependencies.localModelStorage;
      _aiDependencies = dependencies.ai;
      _chatDependencies = dependencies;
    }
    _preferencesStore =
        widget.preferencesStore ?? SharedPreferencesUserPreferencesStore();
    final chronologyResearcher = OpenRouterFranchiseChronologyResearcher(
      engine: AIEngine(
        provider: _aiDependencies.cloudProvider,
        timeout: _aiDependencies.timeout,
      ),
      localEngine: AIEngine(
        provider: _aiDependencies.localProvider,
        timeout: _aiDependencies.timeout,
      ),
    );
    final chronologyCoordinator = FranchiseChronologyCoordinator(
      cache: const SharedPreferencesFranchiseChronologyCache(),
      research: chronologyResearcher.research,
      verifyEvidence: chronologyResearcher.verifyEvidence,
    );
    _franchiseChronologyResolver = chronologyCoordinator.resolve;
  }

  @override
  void dispose() {
    if (_ownsDependencies) unawaited(_disposeOwnedAI());
    super.dispose();
  }

  Future<void> _disposeOwnedAI() async {
    await _chatDependencies.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SystemCorePalette.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                _GuardHeader(onProfilePressed: () => _selectTab(4)),
                Expanded(child: _buildTab()),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        decoration: BoxDecoration(
          color: SystemCorePalette.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: SystemCorePalette.green.withValues(alpha: 0.22),
          ),
          boxShadow: [
            BoxShadow(
              color: SystemCorePalette.green.withValues(alpha: 0.06),
              blurRadius: 24,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BottomNavigationBar(
            elevation: 0,
            currentIndex: _selectedTab,
            onTap: _selectTab,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.transparent,
            selectedItemColor: SystemCorePalette.green,
            unselectedItemColor: SystemCorePalette.muted,
            selectedIconTheme: const IconThemeData(size: 20),
            unselectedIconTheme: const IconThemeData(size: 20),
            selectedFontSize: 10,
            unselectedFontSize: 10,
            showSelectedLabels: true,
            showUnselectedLabels: true,
            items: const [
              BottomNavigationBarItem(
                icon: SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(Icons.dynamic_feed_outlined, size: 20),
                ),
                activeIcon: SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(Icons.dynamic_feed_outlined, size: 20),
                ),
                label: 'Лента',
              ),
              BottomNavigationBarItem(
                icon: SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(Icons.auto_awesome, size: 20),
                ),
                activeIcon: SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(Icons.auto_awesome, size: 20),
                ),
                label: 'AI',
              ),
              BottomNavigationBarItem(
                icon: SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(Icons.movie_outlined, size: 20),
                ),
                activeIcon: SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(Icons.movie_outlined, size: 20),
                ),
                label: 'Медиа',
              ),
              BottomNavigationBarItem(
                icon: SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(Icons.favorite_border, size: 20),
                ),
                activeIcon: SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(Icons.favorite_border, size: 20),
                ),
                label: 'Избранное',
              ),
              BottomNavigationBarItem(
                icon: SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(Icons.settings_outlined, size: 20),
                ),
                activeIcon: SizedBox(
                  width: 24,
                  height: 24,
                  child: Icon(Icons.settings_outlined, size: 20),
                ),
                label: 'Настройки',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab() {
    return switch (_selectedTab) {
      0 => NewsCenterPage(
        aiEngine: _aiDependencies.engine,
        legacyPreferences: widget.preferences,
        preferencesStore: _preferencesStore,
      ),
      1 => AIChatPage(dependencies: _chatDependencies),
      2 => MediaPage(
        preferences: widget.preferences,
        searchService: MediaSearchService(
          franchiseChronologyResolver: _franchiseChronologyResolver,
        ),
      ),
      3 => FavoritesPage(),
      _ => _buildSettings(),
    };
  }

  Widget _buildSettings() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SegmentedButton<int>(
            key: const ValueKey('settings-section-selector'),
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.public),
                label: Text('Сеть'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.memory),
                label: Text('Локальная AI'),
              ),
              ButtonSegment(
                value: 2,
                icon: Icon(Icons.movie_filter_outlined),
                label: Text('Каталог'),
              ),
            ],
            selected: {_selectedSettingsTab},
            onSelectionChanged: (selection) {
              setState(() => _selectedSettingsTab = selection.first);
            },
          ),
        ),
        Expanded(
          child: switch (_selectedSettingsTab) {
            0 => NetworkSettingsPage(
              preferences: widget.preferences,
              preferencesStore: _preferencesStore,
            ),
            1 => LocalModelSettingsPage(
              storage: _localModelStorage,
              aiDependencies: _aiDependencies,
            ),
            _ => const MediaCatalogSettingsPage(),
          },
        ),
      ],
    );
  }

  void _selectTab(int index) {
    setState(() => _selectedTab = index);
  }
}

class _GuardHeader extends StatelessWidget {
  const _GuardHeader({required this.onProfilePressed});

  final VoidCallback onProfilePressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SystemCorePalette.panelElevated, SystemCorePalette.panel],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: SystemCorePalette.green.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: SystemCorePalette.green.withValues(alpha: 0.06),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: SystemCorePalette.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: SystemCorePalette.green.withValues(alpha: 0.65),
                ),
                boxShadow: [
                  BoxShadow(
                    color: SystemCorePalette.green.withValues(alpha: 0.10),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: const Icon(
                Icons.hub_rounded,
                color: SystemCorePalette.green,
                size: 22,
              ),
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OMNI AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'PERSONAL AI SYSTEM',
                    style: TextStyle(
                      color: SystemCorePalette.green,
                      fontSize: 9,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Профиль',
              onPressed: onProfilePressed,
              icon: const Icon(Icons.tune_rounded),
              color: SystemCorePalette.muted,
            ),
          ],
        ),
      ),
    );
  }
}
