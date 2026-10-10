import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/features/favorites/data/interest_feedback_repository.dart';

void main() {
  late _MemoryFeedbackStore store;
  late InterestFeedbackRepository repository;

  setUp(() {
    store = _MemoryFeedbackStore();
    repository = InterestFeedbackRepository(store: store);
  });

  test('persists normalized less-interested topics without duplicates', () async {
    await repository.addLessInterested([' Anime ', 'anime', 'SCI-FI']);

    expect(await repository.loadLessInterested(), {'anime', 'sci-fi'});
  });

  test('removes feedback topics explicitly', () async {
    await repository.addLessInterested(['anime', 'manga']);

    final remaining = await repository.removeLessInterested(['anime']);

    expect(remaining, {'manga'});
    expect(await repository.loadLessInterested(), {'manga'});
  });
}

class _MemoryFeedbackStore implements InterestFeedbackStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
