import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omni_ai/features/news/services/news_reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('reminder settings default to disabled', () async {
    final service = NewsReminderService();

    final settings = await service.loadSettings();

    expect(settings.morning, isFalse);
    expect(settings.evening, isFalse);
  });

  test('restores morning and evening reminder settings independently', () async {
    SharedPreferences.setMockInitialValues({
      'news_reminder_morning_enabled': true,
      'news_reminder_evening_enabled': false,
    });
    final service = NewsReminderService();

    final settings = await service.loadSettings();

    expect(settings.morning, isTrue);
    expect(settings.evening, isFalse);
  });
}
