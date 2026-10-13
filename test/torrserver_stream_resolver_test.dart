import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/data/torrserver_stream_resolver.dart';

void main() {
  const resolver = TorrServerStreamResolver();
  final magnet = Uri.parse(
    'magnet:?xt=urn:btih:0123456789012345678901234567890123456789&dn=Sample%20Film',
  );

  test('builds a TorrServer stream URL and preserves the full magnet link', () {
    final uri = resolver.resolve(
      endpoint: 'http://192.168.1.20:8090/',
      magnetUri: magnet,
    );

    expect(uri.origin, 'http://192.168.1.20:8090');
    expect(uri.path, '/stream');
    expect(uri.queryParameters['link'], magnet.toString());
    expect(uri.queryParameters['play'], 'true');
    expect(uri.queryParameters.containsKey('index'), isFalse);
  });

  test('selects a specific torrent file index for a series episode', () {
    final uri = resolver.resolve(
      endpoint: 'https://media.example',
      magnetUri: magnet,
      fileIndex: 4,
    );

    expect(uri.queryParameters['index'], '4');
    expect(uri.queryParameters['link'], magnet.toString());
  });

  test('allows autoplay to be explicitly disabled', () {
    final uri = resolver.resolve(
      endpoint: 'http://media.example:8090',
      magnetUri: magnet,
      play: false,
    );

    expect(uri.queryParameters['play'], 'false');
  });

  test('rejects invalid endpoints and non-magnet sources', () {
    expect(
      () => resolver.resolve(endpoint: 'not a url', magnetUri: magnet),
      throwsArgumentError,
    );
    expect(
      () => resolver.resolve(
        endpoint: 'http://media.example:8090',
        magnetUri: Uri.parse('https://example.com/video.mp4'),
      ),
      throwsArgumentError,
    );
  });

  test('rejects negative file indices', () {
    expect(
      () => resolver.resolve(
        endpoint: 'http://media.example:8090',
        magnetUri: magnet,
        fileIndex: -1,
      ),
      throwsRangeError,
    );
  });
}
