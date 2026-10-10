enum FavoriteCategory {
  movie,
  series,
  anime,
  manga,
  trailer,
}

extension FavoriteCategoryLabel on FavoriteCategory {
  String get label => switch (this) {
    FavoriteCategory.movie => 'Фильмы',
    FavoriteCategory.series => 'Сериалы',
    FavoriteCategory.anime => 'Аниме',
    FavoriteCategory.manga => 'Манга',
    FavoriteCategory.trailer => 'Трейлеры',
  };
}

class FavoriteItem {
  const FavoriteItem({
    required this.id,
    required this.title,
    required this.category,
    required this.addedAt,
    this.description = '',
    this.imageUrl,
    this.sourceUrl,
    this.releaseDate,
    this.releaseDateSourceUrl,
  });

  final String id;
  final String title;
  final FavoriteCategory category;
  final DateTime addedAt;
  final String description;
  final String? imageUrl;
  final String? sourceUrl;
  final DateTime? releaseDate;
  final String? releaseDateSourceUrl;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'category': category.name,
    'addedAt': addedAt.toIso8601String(),
    'description': description,
    'imageUrl': imageUrl,
    'sourceUrl': sourceUrl,
    'releaseDate': releaseDate?.toIso8601String(),
    'releaseDateSourceUrl': releaseDateSourceUrl,
  };

  static FavoriteItem? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'];
    final title = value['title'];
    final categoryName = value['category'];
    final addedAtRaw = value['addedAt'];
    if (id is! String ||
        id.trim().isEmpty ||
        title is! String ||
        title.trim().isEmpty ||
        categoryName is! String ||
        addedAtRaw is! String) {
      return null;
    }
    FavoriteCategory? category;
    for (final candidate in FavoriteCategory.values) {
      if (candidate.name == categoryName) {
        category = candidate;
        break;
      }
    }
    final addedAt = DateTime.tryParse(addedAtRaw);
    if (category == null || addedAt == null) return null;

    return FavoriteItem(
      id: id,
      title: title,
      category: category,
      addedAt: addedAt,
      description: value['description'] is String
          ? value['description'] as String
          : '',
      imageUrl: _safeUrl(value['imageUrl']),
      sourceUrl: _safeUrl(value['sourceUrl']),
      releaseDate: value['releaseDate'] is String
          ? DateTime.tryParse(value['releaseDate'] as String)
          : null,
      releaseDateSourceUrl: _safeUrl(value['releaseDateSourceUrl']),
    );
  }

  static String? _safeUrl(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !const {'https', 'http'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      return null;
    }
    return uri.toString();
  }
}
