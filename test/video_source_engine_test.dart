import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/data/video_source_engine.dart';
import 'package:omni_ai/features/media/data/video_source_provider.dart';

class _FakeProvider implements VideoSourceProvider {
  _FakeProvider(this.id, this.resolution);

  @override
  final String id;

  final PlaybackResolution? resolution;

  int calls = 0;

  @override
  Future<PlaybackResolution> resolve(PlaybackRequest request) async {
    calls++;
    final result = resolution;
    if (result == null) throw StateError('provider unavailable');
    return result;
  }
}

void main() {
  const request = PlaybackRequest(
    mediaId: 'kinopoisk:123',
    title: 'Пример',
    kind: PlaybackMediaKind.movie,
  );

  test('combines valid variants and deduplicates identical options', () async {
    final first = _FakeProvider(
      'first',
      PlaybackResolution(
        providerId: 'first',
        variants: const [
          PlaybackVariant(url: 'https://cdn.example/movie.m3u8', quality: '1080p'),
        ],
      ),
    );
    final second = _FakeProvider(
      'second',
      PlaybackResolution(
        providerId: 'second',
        variants: const [
          PlaybackVariant(url: 'https://cdn.example/movie.m3u8', quality: '1080p'),
          PlaybackVariant(url: 'https://cdn.example/movie-720.m3u8', quality: '720p'),
        ],
      ),
    );

    final result = await VideoSourceEngine([first, second]).resolve(request);

    expect(result.variants, hasLength(2));
    expect(result.hasPlayableVariants, isTrue);
    expect(result.providerId, 'first,second');
  });

  test('isolates provider failures', () async {
    final broken = _FakeProvider('broken', null);
    final working = _FakeProvider(
      'working',
      PlaybackResolution(
        providerId: 'working',
        variants: const [
          PlaybackVariant(url: 'https://cdn.example/movie.mp4'),
        ],
      ),
    );

    final result = await VideoSourceEngine([broken, working]).resolve(request);

    expect(result.hasPlayableVariants, isTrue);
    expect(result.variants.single.url, 'https://cdn.example/movie.mp4');
  });

  test('caches successful resolutions and supports manual invalidation', () async {
    final provider = _FakeProvider(
      'working',
      PlaybackResolution(
        providerId: 'working',
        variants: const [
          PlaybackVariant(url: 'https://cdn.example/movie.mp4'),
        ],
      ),
    );
    final engine = VideoSourceEngine([provider]);

    await engine.resolve(request);
    await engine.resolve(request);
    expect(provider.calls, 1);

    engine.clearCache();
    await engine.resolve(request);
    expect(provider.calls, 2);
  });

  test('does not cache empty results', () async {
    final provider = _FakeProvider(
      'empty',
      PlaybackResolution(providerId: 'empty', variants: const []),
    );
    final engine = VideoSourceEngine([provider]);

    await engine.resolve(request);
    await engine.resolve(request);

    expect(provider.calls, 2);
  });
}
