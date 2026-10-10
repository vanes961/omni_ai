import 'package:flutter/material.dart';

import 'package:omni_ai/features/favorites/data/favorite_item.dart';
import 'package:omni_ai/features/favorites/data/interest_feedback_repository.dart';
import 'package:omni_ai/features/favorites/data/favorites_repository.dart';
import 'package:omni_ai/features/favorites/services/favorite_interest_analytics.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class FavoritesPage extends StatefulWidget {
  FavoritesPage({
    super.key,
    FavoritesRepository? repository,
    InterestFeedbackRepository? feedbackRepository,
  }) : repository = repository ?? FavoritesRepository(),
       feedbackRepository = feedbackRepository ?? InterestFeedbackRepository();

  final FavoritesRepository repository;
  final InterestFeedbackRepository feedbackRepository;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  FavoriteCategory? _selectedCategory;
  late Future<List<FavoriteItem>> _items;
  Set<String> _lessInterested = <String>{};
  bool _feedbackLoading = true;

  @override
  void initState() {
    super.initState();
    _items = widget.repository.getAll();
    _loadFeedback();
  }

  Future<void> _loadFeedback() async {
    try {
      final topics = await widget.feedbackRepository.loadLessInterested();
      if (!mounted) return;
      setState(() {
        _lessInterested = topics;
        _feedbackLoading = false;
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _feedbackLoading = false);
    }
  }

  Future<void> _removeFeedback(String topic) async {
    final updated = await widget.feedbackRepository.removeLessInterested([topic]);
    if (!mounted) return;
    setState(() => _lessInterested = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Тема «$topic» снова учитывается в новостях.')),
    );
  }

  void _reload() {
    setState(() => _items = widget.repository.getAll());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SystemCorePalette.background,
      appBar: AppBar(
        backgroundColor: SystemCorePalette.panel,
        title: const Text('ИЗБРАННОЕ'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                _CategoryChip(
                  label: 'Все',
                  selected: _selectedCategory == null,
                  onTap: () => setState(() => _selectedCategory = null),
                ),
                for (final category in FavoriteCategory.values)
                  _CategoryChip(
                    label: category.label,
                    selected: _selectedCategory == category,
                    onTap: () => setState(() => _selectedCategory = category),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<FavoriteItem>>(
              future: _items,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: SystemCorePalette.green,
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Не удалось загрузить избранное'),
                  );
                }
                final all = snapshot.data ?? const <FavoriteItem>[];
                final visible = all
                    .where(
                      (item) =>
                          _selectedCategory == null ||
                          item.category == _selectedCategory,
                    )
                    .toList(growable: false);
                final showAnalytics = _selectedCategory == null;
                if (visible.isEmpty && !showAnalytics) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        'В разделе «${_selectedCategory!.label}» пока пусто.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: SystemCorePalette.muted),
                      ),
                    ),
                  );
                }
                final profile = const FavoriteInterestAnalytics().analyze(all);
                final offset = showAnalytics ? 2 : 0;
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: visible.length + offset,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (showAnalytics && index == 0 && all.isNotEmpty) {
                      return _InterestSummary(
                        totalFavorites: all.length,
                        categoryCounts: profile.categoryCounts,
                        topInterests: profile.topInterests
                            .take(6)
                            .toList(growable: false),
                      );
                    }
                    if (showAnalytics && index == (all.isNotEmpty ? 1 : 0)) {
                      return _InterestFeedbackPanel(
                        topics: _lessInterested,
                        loading: _feedbackLoading,
                        onRemove: _removeFeedback,
                      );
                    }
                    if (showAnalytics && all.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Здесь будут сохранённые фильмы, сериалы, аниме, манга и трейлеры.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: SystemCorePalette.muted),
                        ),
                      );
                    }
                    final item = visible[index - offset];
                    return _FavoriteTile(
                      item: item,
                      onRemove: () async {
                        await widget.repository.remove(item.id);
                        if (mounted) _reload();
                      },
                      onMove: (category) async {
                        await widget.repository.move(item.id, category);
                        if (mounted) _reload();
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InterestSummary extends StatelessWidget {
  const _InterestSummary({
    required this.totalFavorites,
    required this.categoryCounts,
    required this.topInterests,
  });

  final int totalFavorites;
  final Map<FavoriteCategory, int> categoryCounts;
  final List<MapEntry<String, double>> topInterests;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SystemCorePalette.panel,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, color: SystemCorePalette.green),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'АНАЛИТИКА ИНТЕРЕСОВ',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '$totalFavorites сохранено',
                style: const TextStyle(
                  color: SystemCorePalette.muted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final category in FavoriteCategory.values)
                Chip(
                  label: Text(
                    '${category.label}: ${categoryCounts[category] ?? 0}',
                    style: const TextStyle(fontSize: 10),
                  ),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                  backgroundColor: SystemCorePalette.background,
                ),
            ],
          ),
          if (topInterests.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Чаще встречающиеся темы',
              style: TextStyle(color: SystemCorePalette.muted, fontSize: 11),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final interest in topInterests)
                  Chip(
                    label: Text(
                      interest.key,
                      style: const TextStyle(fontSize: 10),
                    ),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: SystemCorePalette.green.withValues(alpha: 0.12),
                    labelStyle: const TextStyle(color: SystemCorePalette.green),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InterestFeedbackPanel extends StatelessWidget {
  const _InterestFeedbackPanel({
    required this.topics,
    required this.loading,
    required this.onRemove,
  });

  final Set<String> topics;
  final bool loading;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SystemCorePalette.panel,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune, color: SystemCorePalette.green),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'НАСТРОЙКИ ИНТЕРЕСОВ',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Темы с пониженным приоритетом. Удалите отметку, чтобы снова учитывать их при ранжировании новостей. Настройки хранятся только на устройстве.',
            style: TextStyle(color: SystemCorePalette.muted, fontSize: 11),
          ),
          if (loading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(color: SystemCorePalette.green),
          ] else if (topics.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Пока нет тем с пониженным приоритетом.',
              style: TextStyle(color: SystemCorePalette.muted, fontSize: 11),
            ),
          ] else ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final topic in topics.toList()..sort())
                  InputChip(
                    key: ValueKey('less-interested-$topic'),
                    label: Text(topic),
                    onDeleted: () => onRemove(topic),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
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
        selectedColor: SystemCorePalette.green.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          color: selected ? SystemCorePalette.green : Colors.white70,
          fontSize: 11,
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

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({
    required this.item,
    required this.onRemove,
    required this.onMove,
  });

  final FavoriteItem item;
  final VoidCallback onRemove;
  final ValueChanged<FavoriteCategory> onMove;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SystemCorePalette.panel,
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 70,
            color: SystemCorePalette.background,
            alignment: Alignment.center,
            child: Icon(
              switch (item.category) {
                FavoriteCategory.movie => Icons.movie_outlined,
                FavoriteCategory.series => Icons.tv_outlined,
                FavoriteCategory.anime => Icons.auto_awesome_outlined,
                FavoriteCategory.manga => Icons.menu_book_outlined,
                FavoriteCategory.trailer => Icons.play_circle_outline,
              },
              color: SystemCorePalette.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.category.label,
                  style: const TextStyle(
                    color: SystemCorePalette.green,
                    fontSize: 11,
                  ),
                ),
                if (item.releaseDate != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Выход: ${_formatDate(item.releaseDate!)}',
                    style: const TextStyle(
                      color: SystemCorePalette.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Действия',
            icon: const Icon(Icons.more_vert, color: SystemCorePalette.muted),
            onSelected: (action) {
              if (action == 'remove') {
                onRemove();
              } else {
                final category = FavoriteCategory.values
                    .where((value) => value.name == action)
                    .firstOrNull;
                if (category != null && category != item.category) {
                  onMove(category);
                }
              }
            },
            itemBuilder: (context) => [
              for (final category in FavoriteCategory.values)
                if (category != item.category)
                  PopupMenuItem(
                    value: category.name,
                    child: Text('Переместить: ${category.label}'),
                  ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'remove',
                child: Text('Удалить из избранного'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}
