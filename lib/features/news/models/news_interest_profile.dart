class NewsInterestProfile {
  const NewsInterestProfile({
    this.topics = const <String>[],
    this.languages = const <String>['ru'],
    this.regions = const <String>[],
    this.includeCriticalOutsideInterests = false,
  });

  final List<String> topics;
  final List<String> languages;
  final List<String> regions;
  final bool includeCriticalOutsideInterests;

  NewsInterestProfile copyWith({
    List<String>? topics,
    List<String>? languages,
    List<String>? regions,
    bool? includeCriticalOutsideInterests,
  }) {
    return NewsInterestProfile(
      topics: topics ?? this.topics,
      languages: languages ?? this.languages,
      regions: regions ?? this.regions,
      includeCriticalOutsideInterests:
          includeCriticalOutsideInterests ?? this.includeCriticalOutsideInterests,
    );
  }

  Map<String, Object?> toJson() => {
    'topics': topics,
    'languages': languages,
    'regions': regions,
    'includeCriticalOutsideInterests': includeCriticalOutsideInterests,
  };

  factory NewsInterestProfile.fromJson(Map<String, Object?> json) {
    List<String> readStrings(Object? value) {
      if (value is! List) return const <String>[];
      return value.whereType<String>()
          .map((item) => item.trim().toLowerCase())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: false);
    }

    return NewsInterestProfile(
      topics: readStrings(json['topics']),
      languages: readStrings(json['languages']).isEmpty
          ? const <String>['ru']
          : readStrings(json['languages']),
      regions: readStrings(json['regions']),
      includeCriticalOutsideInterests:
          json['includeCriticalOutsideInterests'] == true,
    );
  }
}
