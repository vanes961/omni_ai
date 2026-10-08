import 'package:flutter/material.dart';
import 'package:omni_ai/features/media/presentation/media_page.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({required this.preferences, super.key});

  final UserPreferences preferences;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedTab = 0;
  int _feedPage = 0;

  static const _feedCards = [
    _FeedCardData(
      number: '01',
      icon: Icons.movie_outlined,
      title: 'МЕДИА-МОДУЛЬ',
      subtitle: 'ПЕРСОНАЛЬНАЯ ПОДБОРКА',
      description: 'Ваш следующий фильм, сериал или тайтл появится здесь.',
      status: 'MODULE STANDBY',
      accent: SystemCorePalette.red,
    ),
    _FeedCardData(
      number: '02',
      icon: Icons.rss_feed_rounded,
      title: 'TELEGRAM // NEWS',
      subtitle: 'ИЗ ВАШИХ ИСТОЧНИКОВ',
      description:
          'Выжимка новостей из выбранных Telegram-каналов появится здесь.',
      status: 'CHANNEL SYNC PENDING',
      accent: SystemCorePalette.green,
    ),
  ];

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OMNI // PERSONAL FEED',
            style: TextStyle(
              color: SystemCorePalette.muted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'ВАША ЛЕНТА',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 22),
          Expanded(
            child: PageView.builder(
              itemCount: _feedCards.length,
              onPageChanged: (page) => setState(() => _feedPage = page),
              itemBuilder: (context, index) =>
                  _FeedCard(data: _feedCards[index]),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _feedCards.length,
              (index) => Container(
                width: index == _feedPage ? 22 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: index == _feedPage
                      ? SystemCorePalette.green
                      : SystemCorePalette.muted,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            widget.preferences.categories.isEmpty
                ? 'ИНТЕРЕСЫ НЕ ВЫБРАНЫ'
                : 'ИНТЕРЕСЫ  //  ${widget.preferences.categories.join(' · ').toUpperCase()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SystemCorePalette.muted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettings() {
    return _ModulePlaceholder(
      eyebrow: '04 // SETTINGS',
      title: 'НАСТРОЙКИ',
      icon: Icons.settings_outlined,
      detail:
          '${widget.preferences.categories.length} ИНТЕРЕСОВ СИНХРОНИЗИРОВАНО',
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

class _FeedCardData {
  const _FeedCardData({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.status,
    required this.accent,
  });

  final String number;
  final IconData icon;
  final String title;
  final String subtitle;
  final String description;
  final String status;
  final Color accent;
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.data});

  final _FeedCardData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: SystemCorePalette.panel,
          border: Border.all(color: data.accent.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    data.number,
                    style: TextStyle(color: data.accent, fontSize: 11),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: data.accent.withValues(alpha: 0.3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'OMNI_FEED',
                    style: TextStyle(
                      color: SystemCorePalette.muted,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Icon(data.icon, size: 38, color: data.accent),
              const SizedBox(height: 20),
              Text(
                data.subtitle,
                style: const TextStyle(
                  color: SystemCorePalette.muted,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                data.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                data.description,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Spacer(),
              Text(
                data.status,
                style: TextStyle(
                  color: data.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModulePlaceholder extends StatelessWidget {
  const _ModulePlaceholder({
    required this.eyebrow,
    required this.title,
    required this.icon,
    this.detail = 'MODULE STANDBY',
  });

  final String eyebrow;
  final String title;
  final IconData icon;
  final String detail;

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
              detail,
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
