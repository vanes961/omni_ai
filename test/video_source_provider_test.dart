import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/data/video_source_provider.dart';

void main() {
  test('accepts only concrete HTTP(S) stream URLs', () {
    const valid = PlaybackVariant(
      url: 'https://cdn.example/video.m3u8',
      quality: '1080p',
      voiceover: 'Русская озвучка',
    );
    const invalid = PlaybackVariant(url: 'javascript:alert(1)');
    const relative = PlaybackVariant(url: '/video.m3u8');

    expect(valid.isHttpStream, isTrue);
    expect(invalid.isHttpStream, isFalse);
    expect(relative.isHttpStream, isFalse);
    expect(valid.toMediaVideoSource()?.quality, '1080p');
    expect(invalid.toMediaVideoSource(), isNull);
  });

  test('normalizes missing quality and blank voiceover safely', () {
    const variant = PlaybackVariant(
      url: 'https://cdn.example/movie.mp4',
      quality: '  ',
      voiceover: ' ',
    );

    final mapped = variant.toMediaVideoSource();

    expect(mapped?.quality, 'Auto');
    expect(mapped?.voiceover, isNull);
  });

  test('resolution filters invalid variants and reports empty results', () {
    final result = PlaybackResolution(
      providerId: 'sample-provider',
      variants: const [
        PlaybackVariant(url: 'https://cdn.example/film.m3u8'),
        PlaybackVariant(url: 'file:///private/film.mp4'),
      ],
    );

    expect(result.variants, hasLength(1));
    expect(result.hasPlayableVariants, isTrue);

    final empty = PlaybackResolution(
      providerId: 'sample-provider',
      variants: const [PlaybackVariant(url: 'not-a-url')],
    );
    expect(empty.hasPlayableVariants, isFalse);
  });

  test('episode requests require positive season and episode numbers', () {
    const movie = PlaybackRequest(
      mediaId: 'kinopoisk:123',
      title: 'Пример',
      kind: PlaybackMediaKind.movie,
    );
    const episode = PlaybackRequest(
      mediaId: 'tmdb:tv:456',
      title: 'Пример сериала',
      kind: PlaybackMediaKind.series,
      season: 1,
      episode: 2,
    );

    expect(movie.targetsEpisode, isFalse);
    expect(episode.targetsEpisode, isTrue);
  });

  test('subtitle URLs are checked independently from stream URLs', () {
    const valid = PlaybackVariant(
      url: 'https://cdn.example/movie.m3u8',
      subtitleUrl: 'https://cdn.example/ru.vtt',
    );
    const invalid = PlaybackVariant(
      url: 'https://cdn.example/movie.m3u8',
      subtitleUrl: 'file:///private/subtitles.vtt',
    );

    expect(valid.hasHttpSubtitles, isTrue);
    expect(invalid.hasHttpSubtitles, isFalse);
  });
}
