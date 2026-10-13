import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/domain/media_hub_contracts.dart';

void main() {
  group('MediaStreamSource', () {
    test('accepts HTTP and HTTPS stream URLs with a host', () {
      final http = MediaStreamSource(
        id: 'http',
        label: 'HTTP source',
        uri: Uri.parse('http://media.example/video.mp4'),
      );
      final https = MediaStreamSource(
        id: 'https',
        label: 'HTTPS source',
        uri: Uri.parse('https://media.example/video.mp4'),
      );

      expect(http.isNetworkStream, isTrue);
      expect(https.isNetworkStream, isTrue);
      expect(http.isSupportedInput, isTrue);
      expect(https.isSupportedInput, isTrue);
    });

    test('rejects non-network schemes and network URLs without a host', () {
      final file = MediaStreamSource(
        id: 'file',
        label: 'Local file',
        uri: Uri.parse('file:///video.mp4'),
      );
      final hostless = MediaStreamSource(
        id: 'hostless',
        label: 'Invalid network source',
        uri: Uri.parse('http:///video.mp4'),
      );

      expect(file.isNetworkStream, isFalse);
      expect(file.isSupportedInput, isFalse);
      expect(hostless.isNetworkStream, isFalse);
      expect(hostless.isSupportedInput, isFalse);
    });

    test('accepts magnet links only when a BitTorrent hash is present', () {
      final valid = MediaStreamSource(
        id: 'magnet-valid',
        label: 'Torrent',
        uri: Uri.parse(
          'magnet:?xt=urn:btih:0123456789012345678901234567890123456789',
        ),
      );
      final missingHash = MediaStreamSource(
        id: 'magnet-invalid',
        label: 'Invalid torrent',
        uri: Uri.parse('magnet:?dn=video'),
      );
      final wrongHashType = MediaStreamSource(
        id: 'magnet-wrong-type',
        label: 'Invalid torrent',
        uri: Uri.parse('magnet:?xt=urn:sha1:0123456789'),
      );
      final malformedHash = MediaStreamSource(
        id: 'magnet-malformed',
        label: 'Malformed torrent hash',
        uri: Uri.parse('magnet:?xt=urn:btih:xyz'),
      );
      final invalidCharacterHash = MediaStreamSource(
        id: 'magnet-invalid-character',
        label: 'Torrent hash with invalid character',
        uri: Uri.parse(
          'magnet:?xt=urn:btih:012345678901234567890123456789012345678z',
        ),
      );
      final base32Hash = MediaStreamSource(
        id: 'magnet-base32',
        label: 'Base32 torrent hash',
        uri: Uri.parse('magnet:?xt=urn:btih:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
      );

      expect(valid.isMagnet, isTrue);
      expect(valid.isSupportedInput, isTrue);
      expect(missingHash.isMagnet, isFalse);
      expect(missingHash.isSupportedInput, isFalse);
      expect(wrongHashType.isMagnet, isFalse);
      expect(malformedHash.isMagnet, isFalse);
      expect(invalidCharacterHash.isMagnet, isFalse);
      expect(base32Hash.isMagnet, isTrue);
    });
  });

  group('MediaEngineSnapshot', () {
    test('reports a buffered fraction for known positive totals', () {
      const snapshot = MediaEngineSnapshot(
        state: MediaEngineState.buffering,
        bufferedBytes: 25,
        totalBytes: 100,
      );

      expect(snapshot.bufferedFraction, 0.25);
    });

    test('clamps over-buffered byte counts to a full buffer', () {
      const snapshot = MediaEngineSnapshot(
        state: MediaEngineState.ready,
        bufferedBytes: 120,
        totalBytes: 100,
      );

      expect(snapshot.bufferedFraction, 1);
    });

    test('returns no fraction when total size is unknown or zero', () {
      const unknown = MediaEngineSnapshot(
        state: MediaEngineState.buffering,
        bufferedBytes: 12,
      );
      const zero = MediaEngineSnapshot(
        state: MediaEngineState.buffering,
        bufferedBytes: 0,
        totalBytes: 0,
      );

      expect(unknown.bufferedFraction, isNull);
      expect(zero.bufferedFraction, isNull);
    });
  });
}
