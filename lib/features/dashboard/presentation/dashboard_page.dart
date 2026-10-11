import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/core/ai_engine/local/local_model_storage.dart';
import 'package:omni_ai/core/di/ai_dependencies.dart';
import 'package:omni_ai/core/di/app_dependencies.dart';
import 'package:omni_ai/features/ai_chat/presentation/ai_chat_page.dart';
import 'package:omni_ai/features/media/presentation/media_page.dart';
import 'package:omni_ai/features/news/presentation/news_center_page.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/settings/presentation/pages/local_model_settings_page.dart';
import 'package:omni_ai/features/settings/presentation/pages/network_settings_page.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';
import 'package:omni_ai/features/telegram/data/telegram_post.dart';
import 'package:omni_ai/features/telegram/presentation/widgets/telegram_post_card.dart';
import 'package:omni_ai/features/telegram/services/telegram_parser_service.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    required this.preferences,
    this.preferencesStore,
    this.dependencies,
    this.telegramService = const TelegramParserService(),
    this.sourceLauncher,
    super.key,
  });

  final UserPreferences preferences;
  final UserPreferencesStore? preferencesStore;
  final AppDependencies? dependencies;
  final TelegramParserService telegramService;
  final TelegramSourceLauncher? sourceLauncher;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedTab = 0;
  int _selectedSettingsTab = 0;
  late final bool _ownsDependencies;
  late final LocalModelStorage _localModelStorage;
  late final AIDependencies _aiDependencies;
  late final AppDependencies _chatDependencies;
  late final UserPreferencesStore _preferencesStore;
  final TextEditingController _feedSearchController = TextEditingController();
  late Future<List<TelegramPost>> _feedFuture;
  String _feedQuery = '';
  String? _selectedFeedChannel;

  @override
  void initState() {
    super.initState();
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
    _feedFuture = widget.telegramService.fetchPosts(widget.preferences);
  }

  @override
  void dispose() {
    _feedSearchController.dispose();
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
      bottomNavigationBar: BottomNavigationBar(
        elevation: 0,
        currentIndex: _selectedTab,
        onTap: _selectTab,
        type: BottomNavigationBarType.fixed,
        backgroundColor: SystemCorePalette.panel,
        selectedItemColor: SystemCorePalette.green,
        unselectedItemColor: SystemCorePalette.muted,
        selectedFontSize: 10,
        unselectedFontSize: 10,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dynamic_feed_outlined),
            activeIcon: Icon(Icons.dynamic_feed),
            label: 'Лента',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            activeIcon: Icon(Icons.chat_bubble),
            label: 'AI',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.movie_outlined),
            activeIcon: Icon(Icons.movie),
            label: 'Медиа',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_border),
            activeIcon: Icon(Icons.favorite),
            label: 'Семья & Здоровье',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }

  Widget _buildTab() {
    return switch (_selectedTab) {
      0 => _buildFeed(),
      1 => AIChatPage(dependencies: _chatDependencies),
      2 => MediaPage(preferences: widget.preferences),
      3 => const _ModulePlaceholder(
        eyebrow: '03 // FAMILY & HEALTH',
        title: 'СЕМЬЯ & ЗДОРОВЬЕ',
        icon: Icons.favorite_border,
      ),
      _ => _buildSettings(),
    };
  }

  Widget _buildFeed() {
    return FutureBuilder<List<TelegramPost>>(
      future: _feedFuture,
      builder: (context, snapshot) {
        final posts = snapshot.data ?? const <TelegramPost>[];
        final visiblePosts = widget.telegramService.filterPosts(
          posts,
          query: _feedQuery,
          channelName: _selectedFeedChannel,
        );
        final channels = widget.preferences.tgChannels;
        final isLoading =
            snapshot.connectionState != ConnectionState.done &&
            !snapshot.hasData;
        final itemCount =
            1 +
            (isLoading || snapshot.hasError || visiblePosts.isEmpty
                ? 1
                : visiblePosts.length);

        return RefreshIndicator(
          onRefresh: _refreshFeed,
          color: SystemCorePalette.green,
          backgroundColor: SystemCorePalette.panel,
          child: ListView.separated(
            key: const ValueKey('telegram-feed'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            itemCount: itemCount,
            separatorBuilder: (context, index) => index == 0
                ? const SizedBox(height: 14)
                : const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == 0) return _buildFeedHeader(channels);
              if (isLoading) {
                return const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: SystemCorePalette.green,
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return _FeedMessage(
                  message: 'НЕ УДАЛОСЬ ОБНОВИТЬ ЛЕНТУ',
                  actionLabel: 'ПОВТОРИТЬ',
                  onAction: _refreshFeed,
                );
              }
              if (visiblePosts.isEmpty) {
                return _FeedMessage(
                  message: channels.isEmpty
                      ? 'ВЫБЕРИТЕ TELEGRAM-КАНАЛЫ В НАСТРОЙКАХ ПРОФИЛЯ'
                      : 'РЕАЛЬНАЯ TELEGRAM-ЛЕНТА ПОКА НЕ ПОДКЛЮЧЕНА',
                );
              }

              final post = visiblePosts[index - 1];
              return TelegramPostCard(
                post: post,
                sourceLauncher: widget.sourceLauncher,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildFeedHeader(List<String> channels) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'KAIROS HUB  //  PERSONAL FEED',
          style: TextStyle(
            color: SystemCorePalette.muted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'ТВОЙ ЦИФРОВОЙ МИР',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('open-news-center'),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => NewsCenterPage(aiEngine: _aiDependencies.engine)),
              );
            },
            icon: const Icon(Icons.rss_feed, size: 17),
            label: const Text('ОТКРЫТЬ ЦЕНТР НОВОСТЕЙ'),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('telegram-feed-search'),
          controller: _feedSearchController,
          onChanged: (value) => setState(() => _feedQuery = value),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Поиск по каналам и постам',
            hintStyle: const TextStyle(color: SystemCorePalette.muted),
            prefixIcon: const Icon(
              Icons.search,
              color: SystemCorePalette.green,
            ),
            isDense: true,
            filled: true,
            fillColor: SystemCorePalette.panel,
            border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
          ),
        ),
        if (channels.isNotEmpty) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FeedChannelFilter(
                  label: 'Все',
                  selected: _selectedFeedChannel == null,
                  onTap: () => setState(() => _selectedFeedChannel = null),
                ),
                for (final channel in channels)
                  _FeedChannelFilter(
                    label: channel,
                    selected: _selectedFeedChannel == channel,
                    onTap: () => setState(
                      () => _selectedFeedChannel =
                          _selectedFeedChannel == channel ? null : channel,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _refreshFeed() async {
    final refreshed = widget.telegramService.refresh(widget.preferences);
    setState(() {
      _feedFuture = refreshed;
    });
    await refreshed;
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
            ],
            selected: {_selectedSettingsTab},
            onSelectionChanged: (selection) {
              setState(() => _selectedSettingsTab = selection.first);
            },
          ),
        ),
        Expanded(
          child: _selectedSettingsTab == 0
              ? NetworkSettingsPage(
                  preferences: widget.preferences,
                  preferencesStore: _preferencesStore,
                )
              : LocalModelSettingsPage(
                  storage: _localModelStorage,
                  aiDependencies: _aiDependencies,
                ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
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
                  'KAIROS HUB',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'AI-GUARD ACTIVE',
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
            tooltip: 'Профиль и настройки',
            onPressed: onProfilePressed,
            icon: const Icon(Icons.tune_rounded),
            color: SystemCorePalette.muted,
          ),
        ],
      ),
    );
  }
}

class _FeedChannelFilter extends StatelessWidget {
  const _FeedChannelFilter({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: SystemCorePalette.green.withValues(alpha: 0.16),
        labelStyle: TextStyle(
          color: selected ? SystemCorePalette.green : Colors.white70,
          fontSize: 9,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(
            color: selected ? SystemCorePalette.green : Colors.white24,
          ),
        ),
      ),
    );
  }
}

class _FeedMessage extends StatelessWidget {
  const _FeedMessage({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SystemCorePalette.muted,
              fontSize: 11,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _ModulePlaceholder extends StatelessWidget {
  const _ModulePlaceholder({
    required this.eyebrow,
    required this.title,
    required this.icon,
  });

  final String eyebrow;
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              eyebrow,
              style: const TextStyle(
                color: SystemCorePalette.muted,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 18),
            Icon(icon, size: 42, color: SystemCorePalette.green),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'MODULE STANDBY',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: SystemCorePalette.muted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
