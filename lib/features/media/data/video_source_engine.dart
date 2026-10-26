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
  }) : providers = List<VideoSourceProvider>.unmodifiable(providers);

  final List<VideoSourceProvider> providers;
  final Duration requestTimeout;
  final Duration cacheTtl;
  final int maxCacheEntries;

  final Map<String, _CachedResolution> _cache = {};

  List<String> get providerIds =>
      List<String>.unmodifiable(providers.map((provider) => provider.id));

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

    final results = await Future.wait(
      providers.map((provider) async {
        try {
          return await provider
              .resolve(request)
              .timeout(requestTimeout);
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
