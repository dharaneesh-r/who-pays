import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../data/local/prefs_service.dart';
import '../domain/streak.dart';

/// The one reason to open this app on a quiet Tuesday.
///
/// A streak is only worth anything if something reminds you it is about to
/// end. Everything else in the app is event-driven — somebody has to organise
/// a dinner — so without this there is nothing bringing anyone back.
///
/// Deliberately one notification a day, in the early evening, and only while a
/// streak is actually alive. Nagging someone with no streak just gets the app
/// uninstalled.
class ReminderService {
  ReminderService(this._prefs);

  final PrefsService _prefs;
  final _plugin = FlutterLocalNotificationsPlugin();

  bool _ready = false;

  static const _id = 1001;
  static const _channelId = 'streak_reminder';

  /// 19:30 — after most people have sat down to eat, early enough that there
  /// is still an evening left to play.
  static const reminderHour = 19;
  static const reminderMinute = 30;

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (_) {
      // A device that refuses notifications still plays the game.
      _ready = false;
    }
  }

  /// Asks for permission. Android 13+ only; older versions grant it at install.
  Future<bool> requestPermission() async {
    await init();
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Re-scheduled after every round, because the message names the streak.
  ///
  /// Nothing is scheduled when the streak is dead, when the reminder is turned
  /// off, or when today has already been played — the streak is safe, so there
  /// is nothing to warn about.
  Future<void> refresh(Streak streak) async {
    await init();
    if (!_ready) return;

    await cancel();

    if (!shouldRemind(streak, enabled: await _prefs.remindersEnabled())) return;

    final nights = streak.current == 1 ? 'night' : 'nights';

    try {
      await _plugin.zonedSchedule(
        id: _id,
        title: '${streak.current} $nights in a row',
        body: 'Play one round tonight to keep the streak alive.',
        scheduledDate: _nextReminderTime(),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Streak reminders',
            channelDescription:
                'An evening nudge when your phone-free streak is about to end.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        // Inexact on purpose: exact alarms need a special permission on
        // Android 12+ that Play scrutinises, and a reminder does not need to
        // land on the exact second.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {/* scheduling is best-effort */}
  }

  Future<void> cancel() async {
    try {
      await _plugin.cancel(id: _id);
    } catch (_) {}
  }

  /// Today at the reminder time, or tomorrow if that has already passed.
  tz.TZDateTime _nextReminderTime() {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      reminderHour,
      reminderMinute,
    );
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    return when;
  }
}

final reminderServiceProvider = Provider<ReminderService>(
  (ref) => ReminderService(ref.watch(prefsServiceProvider)),
);
