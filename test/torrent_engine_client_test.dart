import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/data/torrent_engine_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('omni_ai/torrent_engine');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('reads native torrent status and file metadata', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getTorrentStatus':
              return <String, Object?>{
                'metadataReady': true,
                'progress': 0.25,
                'downloadRateBytesPerSecond': 1024,
                'downloadedBytes': 4096,
                'finished': false,
                'name': 'sample',
                'fileCount': 1,
              };
            case 'listTorrentFiles':
              return <String, Object?>{
                'metadataReady': true,
                'files': <Map<String, Object?>>[
                  <String, Object?>{
                    'index': 0,
                    'path': 'sample/video.mkv',
                    'name': 'video.mkv',
                    'sizeBytes': 16384,
                  },
                ],
              };
            default:
              return <String, Object?>{};
          }
        });

    final client = TorrentEngineClient(channel: channel);
    final status = await client.getStatus();
    final files = await client.listFiles();

    expect(status.metadataReady, isTrue);
    expect(status.progress, 0.25);
    expect(status.downloadRateBytesPerSecond, 1024);
    expect(status.fileCount, 1);
    expect(files, hasLength(1));
    expect(files.single.name, 'video.mkv');
    expect(files.single.sizeBytes, 16384);
  });

  test('rejects a negative file index before calling native code', () async {
    var invoked = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          invoked = true;
          return <String, Object?>{};
        });

    final client = TorrentEngineClient(channel: channel);

    expect(() => client.selectFile(-1), throwsArgumentError);
    expect(invoked, isFalse);
  });
}
