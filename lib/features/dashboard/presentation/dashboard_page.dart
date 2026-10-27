import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:omni_ai/core/diagnostics/diagnostic_report.dart';
import 'package:omni_ai/core/ai_engine/local/local_model_storage.dart';
import 'package:omni_ai/core/di/ai_dependencies.dart';
import 'package:omni_ai/core/di/app_dependencies.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:omni_ai/features/media/data/internet_archive_playback_provider.dart';
import 'package:omni_ai/features/media/data/source_discovery_service.dart';
import 'package:omni_ai/features/media/data/video_source_engine.dart';
import 'package:omni_ai/features/media/services/franchise_chronology_coordinator.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/media/services/media_catalog_token_store.dart';
import 'package:omni_ai/features/media/services/openrouter_franchise_chronology_researcher.dart';
import 'package:omni_ai/features/media/services/shared_preferences_franchise_chronology_cache.dart';
import 'package:omni_ai/features/ai_chat/presentation/floating_ai_companion.dart';
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
  late final http.Client _mediaSourceHttpClient;
  late final VideoSourceEngine _videoSourceEngine;
  late final SourceDiscoveryService _sourceDiscoveryService;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab.clamp(0, 3).toInt();
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

    _mediaSourceHttpClient = http.Client();
    _videoSourceEngine = VideoSourceEngine(const []);
    _sourceDiscoveryService = SourceDiscoveryService(
      adapters: [InternetArchiveDiscoveryAdapter()],
      probe: InternetArchiveSourceProbe(client: _mediaSourceHttpClient),
      videoSourceEngine: _videoSourceEngine,
      providerFactory: (candidate) => candidate.id == 'internet-archive'
          ? InternetArchivePlaybackProvider(client: _mediaSourceHttpClient)
          : null,
    );
  }

  @override
  void dispose() {
    _mediaSourceHttpClient.close();
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
                _GuardHeader(
                  onProfilePressed: () => _selectTab(3),
                  onDiagnosticsPressed: _runAppDiagnostics,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: _buildTab()),
                      FloatingAICompanion(dependencies: _chatDependencies),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        decoration: BoxDecoration(
          color: SystemCorePalette.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: SystemCorePalette.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 18,
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
            selectedIconTheme: const IconThemeData(size: 22),
            unselectedIconTheme: const IconThemeData(size: 20),
            selectedFontSize: 11,
            unselectedFontSize: 10,
            selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
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

  Future<void> _runAppDiagnostics() async {
    final checks = <DiagnosticCheck>[
      DiagnosticCheck(
        name: 'Основная панель',
        status: DiagnosticStatus.ok,
        details:
            'Загружены разделы: Лента, Медиа, Избранное, Настройки; AI доступен через плавающего помощника',
      ),
      DiagnosticCheck(
        name: 'Профиль приложения',
        status: widget.preferences.categories.isEmpty
            ? DiagnosticStatus.warning
            : DiagnosticStatus.ok,
        details:
            'Сохранённых категорий профиля: '
            '${widget.preferences.categories.length}; '
            'личные значения и названия интересов не включены в отчёт',
      ),
    ];

    try {
      await _aiDependencies.restoreExecutionMode();
      checks.add(
        DiagnosticCheck(
          name: 'Маршрутизация AI',
          status: DiagnosticStatus.ok,
          details:
              'Режим: ${_aiDependencies.executionMode.name}; '
              'локальный провайдер: ${_aiDependencies.localProvider.id}; '
              'облачный провайдер: ${_aiDependencies.cloudProvider.id}',
        ),
      );
    } on Object {
      checks.add(
        const DiagnosticCheck(
          name: 'Маршрутизация AI',
          status: DiagnosticStatus.error,
          details: 'Не удалось восстановить сохранённый режим AI',
        ),
      );
    }

    try {
      final hasCloudKey = await _aiDependencies.hasCloudApiKey;
      checks.add(
        DiagnosticCheck(
          name: 'Облачный AI',
          status: hasCloudKey ? DiagnosticStatus.ok : DiagnosticStatus.warning,
          details: hasCloudKey
              ? 'Ключ настроен; секретное значение не читается в отчёт'
              : 'Ключ OpenRouter не настроен на устройстве',
        ),
      );
    } on Object {
      checks.add(
        const DiagnosticCheck(
          name: 'Облачный AI',
          status: DiagnosticStatus.error,
          details: 'Не удалось проверить состояние защищённого хранилища',
        ),
      );
    }

    try {
      final installed = await _localModelStorage.isDownloaded(
        LocalModelCatalog.qwen3Small,
      );
      checks.add(
        DiagnosticCheck(
          name: 'Локальная модель',
          status: installed ? DiagnosticStatus.ok : DiagnosticStatus.warning,
          details: installed
              ? 'Файл модели найден и прошёл проверку размера; checksum отдельно не проверялся'
              : 'Файл модели отсутствует или меньше ожидаемого размера',
        ),
      );
    } on Object {
      checks.add(
        const DiagnosticCheck(
          name: 'Локальная модель',
          status: DiagnosticStatus.error,
          details: 'Не удалось проверить файл локальной модели',
        ),
      );
    }

    try {
      final token = await SecureMediaCatalogTokenStore().readToken();
      checks.add(
        DiagnosticCheck(
          name: 'Медиакаталог',
          status: token == null
              ? DiagnosticStatus.warning
              : DiagnosticStatus.ok,
          details: token == null
              ? 'TMDB-токен не настроен; значение токена не запрашивалось'
              : 'TMDB-токен найден в защищённом хранилище; доступность каталога отдельно не проверялась',
        ),
      );
    } on Object {
      checks.add(
        const DiagnosticCheck(
          name: 'Медиакаталог',
          status: DiagnosticStatus.warning,
          details: 'Не удалось прочитать статус защищённого хранилища TMDB',
        ),
      );
    }

    try {
      final response = await http
          .get(
            Uri.https('news.google.com', '/rss/search', {
              'q': 'technology',
              'hl': 'ru',
              'gl': 'RU',
              'ceid': 'RU:ru',
            }),
          )
          .timeout(const Duration(seconds: 10));
      checks.add(
        DiagnosticCheck(
          name: 'Интернет и RSS endpoint',
          status: response.statusCode >= 200 && response.statusCode < 300
              ? DiagnosticStatus.ok
              : DiagnosticStatus.error,
          details: response.statusCode >= 200 && response.statusCode < 300
              ? 'RSS endpoint ответил HTTP ${response.statusCode}; это не гарантирует загрузку и фильтрацию персональной ленты'
              : 'RSS endpoint ответил HTTP ${response.statusCode}',
        ),
      );
    } on Object catch (error) {
      checks.add(
        DiagnosticCheck(
          name: 'Интернет и RSS endpoint',
          status: DiagnosticStatus.error,
          details:
              'Пробный запрос не прошёл: ${error.runtimeType}; '
              'проверьте соединение, DNS, VPN/прокси и повторите тест',
        ),
      );
    }

    checks.addAll(const [
      DiagnosticCheck(
        name: 'Реальный ответ AI',
        status: DiagnosticStatus.notChecked,
        details:
            'Базовая проверка не отправляет запрос модели. Отправьте короткий запрос через плавающего AI-компаньона или используйте тест облака в настройках.',
      ),
      DiagnosticCheck(
        name: 'Воспроизведение медиа',
        status: DiagnosticStatus.notChecked,
        details:
            'Нужно открыть реальный источник и проверить запуск, перемотку и полноэкранный режим; тестовые ссылки автоматически не запускаются.',
      ),
      DiagnosticCheck(
        name: 'Персональная новостная лента',
        status: DiagnosticStatus.notChecked,
        details:
            'Для счётчиков RSS, локализации, персонализации и отображаемых статей откройте вкладку «Лента» и сформируйте подробный диагностический отчёт.',
      ),
    ]);

    final report = DiagnosticReport(createdAt: DateTime.now(), checks: checks);
    final reportText = report.toPlainText();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SystemCorePalette.panel,
        title: const Text('Полная проверка OMNI AI'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              reportText,
              style: const TextStyle(color: Colors.white70, height: 1.45),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ЗАКРЫТЬ'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: reportText));
              if (mounted && dialogContext.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Отчёт скопирован')),
                );
                Navigator.of(dialogContext).pop();
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('КОПИРОВАТЬ ОТЧЁТ'),
          ),
        ],
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
      1 => MediaPage(
        preferences: widget.preferences,
        searchService: MediaSearchService(
          franchiseChronologyResolver: _franchiseChronologyResolver,
        ),
        sourceDiscoveryService: _sourceDiscoveryService,
        videoSourceEngine: _videoSourceEngine,
        onOpenCatalogSettings: () {
          setState(() {
            _selectedTab = 3;
            _selectedSettingsTab = 2;
          });
        },
      ),
      2 => FavoritesPage(),
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
  const _GuardHeader({
    required this.onProfilePressed,
    required this.onDiagnosticsPressed,
  });

  final VoidCallback onProfilePressed;
  final VoidCallback onDiagnosticsPressed;

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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SystemCorePalette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
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
                color: SystemCorePalette.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: SystemCorePalette.green.withValues(alpha: 0.38),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
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
                    'Ваш личный помощник',
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
              tooltip: 'Проверить приложение',
              onPressed: onDiagnosticsPressed,
              icon: const Icon(Icons.health_and_safety_outlined),
              color: SystemCorePalette.green,
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
