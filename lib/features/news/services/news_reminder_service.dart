import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Schedules local reminders to open the app and refresh a personalised digest.
/// It deliberately does not claim to fetch or generate news while the app is closed.
class NewsReminderService {
  NewsReminderService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _morningKey = 'news_reminder_morning_enabled';
  static const _eveningKey = 'news_reminder_evening_enabled';
  static const _morningId = 7101;
  static const _eveningId = 7102;

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<({bool morning, bool evening})> loadSettings() async {
    final preferences = await SharedPreferences.getInstance();
    return (
      morning: preferences.getBool(_morningKey) ?? false,
      evening: preferences.getBool(_eveningKey) ?? false,
    );
  }

  Future<bool> setMorningEnabled(bool enabled) async {
    await initialize();
    if (enabled && !await _requestPermission()) return false;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_morningKey, enabled);
    if (enabled) {
      await _scheduleDaily(
        id: _morningId,
        hour: 8,
        minute: 0,
        title: 'Твой утренний обзор готов к обновлению',
        body: 'Открой OMNI AI, чтобы загрузить новости по твоим интересам и создать AI-дайджест.',
      );
    } else {
      await _plugin.cancel(_morningId);
    }
    return true;
  }

  Future<bool> setEveningEnabled(bool enabled) async {
    await initialize();
    if (enabled && !await _requestPermission()) return false;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_eveningKey, enabled);
    if (enabled) {
      await _scheduleDaily(
        id: _eveningId,
        hour: 18,
        minute: 0,
        title: 'Вечерний обзор OMNI AI',
        body: 'Открой OMNI AI, чтобы обновить персональные новости и создать AI-дайджест.',
      );
    } else {
      await _plugin.cancel(_eveningId);
    }
    return true;
  }

  Future<bool> _requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  Future<void> _scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      next,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'omni_news_reminders',
          'Напоминания о новостях',
          channelDescription: 'Напоминания открыть OMNI AI и обновить персональные новости.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexact,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}
