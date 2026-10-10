import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/core/ai_engine/local/local_model_storage.dart';
import 'package:omni_ai/core/di/ai_dependencies.dart';
import 'package:omni_ai/core/di/app_dependencies.dart';
import 'package:omni_ai/features/media/presentation/media_page.dart';
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
      _localModelStorage = LocalModelStorage();
      _aiDependencies = AIDependencies(localModelStorage: _localModelStorage);
    } else {
      _localModelStorage = dependencies.localModelStorage;
      _aiDependencies = dependencies.ai;
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
    await _aiDependencies.dispose();
    _localModelStorage.dispose();
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
                _GuardHeader(onProfilePressed: () => _selectTab(3)),
                Expanded(child: _buildTab()),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTab,
        onTap: _selectTab,
        type: BottomNavigationBarType.fixed,
        backgroundColor: SystemCorePalette.panel,
        selectedItemColor: SystemCorePalette.green,
        unselectedItemColor: SystemCorePalette.muted,
        selectedFontSize: 10,
        unselectedFontSize: 10,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dynamic_feed_outlined),
            activeIcon: Icon(Icons.dynamic_feed),
            label: 'Лента',
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
      1 => MediaPage(preferences: widget.preferences),
      2 => const _ModulePlaceholder(
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
                      : 'ПОСТЫ НЕ НАЙДЕНЫ',
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
          'OMNI // TELEGRAM FEED',
          style: TextStyle(
            color: SystemCorePalette.muted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'ВАША ЛЕНТА',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
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
      padding: const EdgeInsets.fromLTRB(22, 12, 14, 12),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: SystemCorePalette.green),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'AI-GUARD ACTIVE',
              style: TextStyle(
                color: SystemCorePalette.green,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Профиль',
            onPressed: onProfilePressed,
            icon: const Icon(Icons.account_circle_outlined),
            color: Colors.white70,
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
