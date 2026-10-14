import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/services/shared_preferences_franchise_chronology_cache.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const entries = [
    MediaFranchiseEntry(
      id: 'tmdb:movie:10',
      title: 'Film A',
      overview: 'Overview A',
      releaseDate: '2020-01-01',
      posterUrl: 'https://example.org/a.jpg',
      chronologyOrder: 1,
      chronologySourceUrl: 'https://example.org/a',
    ),
    MediaFranchiseEntry(
      id: 'tmdb:movie:20',
      title: 'Film B',
      overview: 'Overview B',
      releaseDate: '2021-01-01',
      posterUrl: 'https://example.org/b.jpg',
      chronologyOrder: 2,
      chronologySpoilerRisk: true,
      chronologySourceUrl: 'https://example.org/b',
    ),
  ];

  test('persists and restores verified chronology metadata', () async {
    const cache = SharedPreferencesFranchiseChronologyCache();
    await cache.write('franchise:test', entries);

    final restored = await cache.read('franchise:test');

    expect(restored, isNotNull);
    expect(restored!.map((entry) => entry.id), entries.map((entry) => entry.id));
    expect(restored.first.chronologyOrder, 1);
    expect(restored.last.chronologyOrder, 2);
    expect(restored.last.chronologySpoilerRisk, isTrue);
    expect(
      restored.first.chronologySourceUrl,
      'https://example.org/a',
    );
  });

  test('returns null for malformed cached payload', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'omni_ai.franchise_chronology.v1.franchise%3Atest',
      '{not-json',
    );

    const cache = SharedPreferencesFranchiseChronologyCache();
    expect(await cache.read('franchise:test'), isNull);
  });

  test('returns null for expired cache', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'omni_ai.franchise_chronology.v1.franchise%3Atest',
      '{"version":1,"savedAt":0,"entries":[]}',
    );

    const cache = SharedPreferencesFranchiseChronologyCache(
      maxAge: Duration(days: 1),
    );
    expect(await cache.read('franchise:test'), isNull);
  });
}
