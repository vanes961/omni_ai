import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/sources/media_source.dart';
import 'package:omni_ai/features/media/sources/media_source_engine.dart';

void main() {
  group('MediaSourceEngine', () {
    test('deduplicates matching titles and keeps the richer card', () async {
      final engine = MediaSourceEngine([
        _FakeSource('minimal', [
          _item(title: 'Дюна', poster: '', description: ''),
        ]),
        _FakeSource('rich', [
          _item(
            title: 'Дюна',
            poster: 'https://images.example/poster.jpg',
            description: 'Фантастический фильм',
          ),
        ]),
      ]);

      final results = await engine.search(
        'дюна',
        kind: MediaSourceKind.movie,
      );

      expect(results, hasLength(1));
      expect(results.single.posterUrl, 'https://images.example/poster.jpg');
      expect(results.single.description, 'Фантастический фильм');
    });

    test('a failed source does not hide results from other sources', () async {
      final engine = MediaSourceEngine([
        _FakeSource('offline', const [], fail: true),
        _FakeSource('available', [_item(title: 'Прибытие')]),
      ]);

      final results = await engine.search(
        'прибытие',
        kind: MediaSourceKind.movie,
      );

      expect(results, hasLength(1));
      expect(results.single.title, 'Прибытие');
    });

    test('does not return items of a different category', () async {
      final engine = MediaSourceEngine([
        _FakeSource('mixed', [
          _item(title: 'Дюна', type: 'Фильм'),
          _item(title: 'Аркейн', type: 'Сериал'),
        ]),
      ]);

      final results = await engine.search(
        'a',
        kind: MediaSourceKind.movie,
      );

      expect(results.map((item) => item.title), ['Дюна']);
    });

    test('blank queries do not call sources', () async {
      final source = _FakeSource('source', [_item(title: 'Дюна')]);
      final engine = MediaSourceEngine([source]);

      expect(
        await engine.search('   ', kind: MediaSourceKind.movie),
        isEmpty,
      );
      expect(source.calls, 0);
    });
  });
}

class _FakeSource implements MediaSource {
  _FakeSource(this.id, this.items, {this.fail = false});

  @override
  final String id;

  final List<MediaItem> items;
  final bool fail;
  int calls = 0;

  @override
  Set<MediaSourceKind> get supportedKinds => const {
    MediaSourceKind.movie,
    MediaSourceKind.series,
    MediaSourceKind.anime,
  };

  @override
  Future<List<MediaItem>> search(
    String query, {
    required MediaSourceKind kind,
  }) async {
    calls++;
    if (fail) throw StateError('source unavailable');
    return items;
  }
}

MediaItem _item({
  required String title,
  String type = 'Фильм',
  String poster = '',
  String description = '',
}) => MediaItem(
  id: 'test:$title',
  title: title,
  type: type,
  posterUrl: poster,
  rating: 7.0,
  voiceovers: const [],
  videoUrl: '',
  description: description,
);
