import 'package:flutter/material.dart';

import 'package:omni_ai/features/favorites/data/favorite_item.dart';
import 'package:omni_ai/features/favorites/data/favorites_repository.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key, FavoritesRepository? repository})
    : repository = repository ?? FavoritesRepository();

  final FavoritesRepository repository;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  FavoriteCategory? _selectedCategory;
  late Future<List<FavoriteItem>> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.repository.getAll();
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
                if (visible.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        _selectedCategory == null
                            ? 'Здесь будут сохранённые фильмы, сериалы, аниме, манга и трейлеры.'
                            : 'В разделе «${_selectedCategory!.label}» пока пусто.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: SystemCorePalette.muted),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: visible.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _FavoriteTile(
                    item: visible[index],
                    onRemove: () async {
                      await widget.repository.remove(visible[index].id);
                      if (mounted) _reload();
                    },
                    onMove: (category) async {
                      await widget.repository.move(visible[index].id, category);
                      if (mounted) _reload();
                    },
                  ),
                );
              },
            ),
          ),
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
