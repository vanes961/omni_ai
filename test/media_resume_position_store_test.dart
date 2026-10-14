import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/services/media_resume_position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  group('SharedPreferencesMediaResumePositionStore', () {
    late SharedPreferencesMediaResumePositionStore store;

    setUp(() {
      store = SharedPreferencesMediaResumePositionStore();
    });

    test('keeps progress isolated by media and episode', () async {
      await store.save(
        'series-a',
        0,
        const Duration(minutes: 5, seconds: 20),
        const Duration(minutes: 40),
      );

      expect(
        await store.load('series-a', 0),
        const Duration(minutes: 5, seconds: 20),
      );
      expect(await store.load('series-a', 1), isNull);
      expect(await store.load('series-b', 0), isNull);
    });

    test('clears resume position and marks episode watched near the end', () async {
      await store.save(
        'series-a',
        2,
        const Duration(minutes: 39, seconds: 50),
        const Duration(minutes: 40),
      );

      expect(await store.load('series-a', 2), isNull);
      expect(await store.loadWatchedEpisodes('series-a'), contains(2));
    });

    test('ignores tiny startup positions and clears explicit progress', () async {
      await store.save(
        'series-a',
        0,
        const Duration(seconds: 5),
        const Duration(minutes: 40),
      );
      expect(await store.load('series-a', 0), isNull);

      await store.save(
        'series-a',
        0,
        const Duration(minutes: 8),
        const Duration(minutes: 40),
      );
      await store.clear('series-a', 0);

      expect(await store.load('series-a', 0), isNull);
    });

    test('persists watched episode indexes without duplicates', () async {
      await store.markEpisodeWatched('series-a', 1);
      await store.markEpisodeWatched('series-a', 1);
      await store.markEpisodeWatched('series-a', 3);

      expect(await store.loadWatchedEpisodes('series-a'), <int>{1, 3});
    });
  });
}
