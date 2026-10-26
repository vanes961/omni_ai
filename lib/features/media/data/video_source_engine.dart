import 'package:omni_ai/features/media/data/video_source_provider.dart';

/// Runs independently replaceable playback providers without binding the
/// player to a specific catalog or vendor.
///
/// Successful results are cached briefly per request. Failed providers are
/// isolated; a broken source does not prevent other permitted sources from
/// returning variants.
class VideoSourceEngine {
  VideoSourceEngine(
    Iterable<VideoSourceProvider> providers, {
    this.requestTimeout = const Duration(seconds: 12),
    this.cacheTtl = const Duration(minutes: 2),
    this.maxCacheEntries = 50,
  }) : _providers = List<VideoSourceProvider>.of(providers);

  final List<VideoSourceProvider> _providers;
  final Duration requestTimeout;
  final Duration cacheTtl;
  final int maxCacheEntries;

  final Map<String, _CachedResolution> _cache = {};

  /// Current registered providers, exposed as an immutable snapshot.
  List<VideoSourceProvider> get providers =>
      List<VideoSourceProvider>.unmodifiable(_providers);

  List<String> get providerIds =>
      List<String>.unmodifiable(_providers.map((provider) => provider.id));

  /// Registers or replaces a provider by its stable ID.
  ///
  /// Any cached resolutions are invalidated so a newly discovered provider is
  /// visible on the next request rather than after the cache TTL expires.
  void registerProvider(VideoSourceProvider provider) {
    final id = provider.id.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(provider.id, 'provider.id', 'Must not be empty');
    }
    final index = _providers.indexWhere((current) => current.id == id);
    if (index == -1) {
      _providers.add(provider);
    } else {
      _providers[index] = provider;
    }
    clearCache();
  }

  /// Removes a provider by ID and invalidates cached playback resolutions.
  bool unregisterProvider(String providerId) {
    final before = _providers.length;
    _providers.removeWhere((provider) => provider.id == providerId);
    final removed = _providers.length != before;
    if (removed) clearCache();
    return removed;
  }

  /// Resolves options from every provider and combines valid variants.
  ///
  /// The engine does not invent URLs or infer playback from catalog metadata.
  Future<PlaybackResolution> resolve(PlaybackRequest request) async {
    final key = _cacheKey(request);
    final now = DateTime.now();
    final cached = _cache[key];
    if (cached != null && now.difference(cached.savedAt) < cacheTtl) {
      return cached.resolution;
    }
    if (cached != null) _cache.remove(key);

    final activeProviders = providers;
    final results = await Future.wait(
      activeProviders.map((provider) async {
        try {
          return await provider.resolve(request).timeout(requestTimeout);
        } on Object {
          // Isolate a provider failure so another source can still succeed.
          return null;
        }
      }),
    );

    final variants = <String, PlaybackVariant>{};
    final providerNames = <String>[];
    for (var index = 0; index < results.length; index++) {
      final result = results[index];
      if (result == null || !result.hasPlayableVariants) continue;
      providerNames.add(result.providerId);
      for (final variant in result.variants) {
        if (!variant.isHttpStream) continue;
        final identity = [
          variant.url,
          variant.quality ?? '',
          variant.voiceover ?? '',
        ].join('|');
        variants.putIfAbsent(identity, () => variant);
      }
    }

    final resolution = PlaybackResolution(
      providerId: providerNames.join(','),
      variants: variants.values,
      message: variants.isEmpty ? 'Не найден доступный видеопоток.' : null,
    );
    if (variants.isNotEmpty && maxCacheEntries > 0 && cacheTtl > Duration.zero) {
      if (_cache.length >= maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
      _cache[key] = _CachedResolution(resolution, DateTime.now());
    }
    return resolution;
  }

  /// Clears cached results after a playback failure or user-requested refresh.
  void clearCache() => _cache.clear();

  String _cacheKey(PlaybackRequest request) => [
    request.mediaId.trim().toLowerCase(),
    request.kind.name,
    request.season ?? 0,
    request.episode ?? 0,
    request.releaseYear ?? 0,
  ].join('|');
}

class _CachedResolution {
  const _CachedResolution(this.resolution, this.savedAt);

  final PlaybackResolution resolution;
  final DateTime savedAt;
}
