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
    expect(valid.isSupportedSource, isTrue);
    expect(valid.toMediaVideoSource()?.quality, '1080p');
    expect(invalid.toMediaVideoSource(), isNull);
  });

  test('accepts valid magnet links only as torrent resolver inputs', () {
    const valid = PlaybackVariant(
      url: 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Legal%20Video',
    );
    const invalid = PlaybackVariant(url: 'magnet:?dn=missing-hash');
    const malformed = PlaybackVariant(url: 'magnet:?xt=urn:btih:xyz');
    const base32 = PlaybackVariant(
      url: 'magnet:?xt=urn:btih:abcdefghijklmnopqrstuvwxyz234567',
    );

    expect(valid.isMagnetSource, isTrue);
    expect(valid.isSupportedSource, isTrue);
    expect(valid.toMediaVideoSource(), isNull);
    expect(invalid.isSupportedSource, isFalse);
    expect(malformed.isSupportedSource, isFalse);
    expect(base32.isMagnetSource, isTrue);
    expect(base32.isSupportedSource, isTrue);
    expect(base32.toMediaVideoSource(), isNull);
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
        PlaybackVariant(url: 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567'),
        PlaybackVariant(url: 'file:///private/film.mp4'),
      ],
    );

    expect(result.variants, hasLength(2));
    expect(result.variants.map((variant) => variant.isMagnetSource), contains(true));
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
