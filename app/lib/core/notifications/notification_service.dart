import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_planner.dart';

enum ReminderPermission {
  granted,

  /// The user hasn't allowed notifications (Android 13+ asks at runtime).
  notificationsOff,

  /// Notifications are on, but "Alarms & reminders" is off, so Android may
  /// deliver them several minutes late.
  exactAlarmsOff,
}

/// Sent when the user taps a reminder or its "Mark as taken" button.
class DoseNotificationTap {
  const DoseNotificationTap({
    required this.scheduleId,
    required this.scheduledAt,
    required this.markTaken,
  });

  final String scheduleId;
  final DateTime scheduledAt;
  final bool markTaken;
}

/// What the rest of the app needs from the notification system. The real
/// one is [NotificationService]; tests use a fake.
abstract interface class ReminderPlatform {
  Stream<DoseNotificationTap> get taps;
  DoseNotificationTap? takeLaunchTap();
  Future<ReminderPermission> permission();
  Future<bool> requestNotifications();
  Future<void> requestExactAlarms();
  Future<void> openSettings();
  Future<void> replaceAll(List<PlannedReminder> reminders, {required bool exact});
  Future<void> cancel(int id);
  Future<void> cancelAll();
  Future<void> scheduleTest({required bool exact, Duration delay = const Duration(seconds: 10)});
}

/// The only class that talks to flutter_local_notifications. Everything else
/// works with plain Dart objects, which keeps the rest testable.
class NotificationService implements ReminderPlatform {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<DoseNotificationTap>.broadcast();
  DoseNotificationTap? _launchTap;
  bool _ready = false;

  static const _takeAction = 'take';
  static const _channel = AndroidNotificationChannel(
    'dose_reminders',
    'Dose reminders',
    description: 'Alerts when it is time to take a medication.',
    importance: Importance.max,
  );

  @override
  Stream<DoseNotificationTap> get taps => _taps.stream;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Call once in main(). Never throws: if notifications can't start, the
  /// rest of the app still works.
  Future<void> init() async {
    try {
      // Scheduled times must follow the phone's timezone, e.g. Asia/Kuala_Lumpur.
      tz_data.initializeTimeZones();
      try {
        final zone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(zone.identifier));
      } catch (_) {
        tz.setLocalLocation(tz.getLocation('Asia/Kuala_Lumpur'));
      }

      await _initializePlugin('@drawable/ic_stat_pill');
      await _android?.createNotificationChannel(_channel);

      // App was closed and opened by tapping a reminder.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
        _launchTap = _parse(response);
      }
      _ready = true;
    } catch (e, st) {
      developer.log('Notifications unavailable', name: 'NotificationService', error: e, stackTrace: st);
    }
  }

  Future<void> _initializePlugin(String icon) async {
    try {
      await _plugin.initialize(
        settings: InitializationSettings(android: AndroidInitializationSettings(icon)),
        onDidReceiveNotificationResponse: (response) {
          final tap = _parse(response);
          if (tap != null) _taps.add(tap);
        },
      );
    } on PlatformException {
      // The pill icon file wasn't added to android/…/res/drawable yet:
      // fall back to the app icon so reminders still work.
      if (icon == '@mipmap/ic_launcher') rethrow;
      await _initializePlugin('@mipmap/ic_launcher');
    }
  }

  /// The tap that launched the app, if any. Returned only once.
  @override
  DoseNotificationTap? takeLaunchTap() {
    final tap = _launchTap;
    _launchTap = null;
    return tap;
  }

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  @override
  Future<ReminderPermission> permission() async {
    final android = _android;
    if (!_ready || android == null) return ReminderPermission.granted;
    if (await android.areNotificationsEnabled() == false) return ReminderPermission.notificationsOff;
    if (await android.canScheduleExactNotifications() == false) return ReminderPermission.exactAlarmsOff;
    return ReminderPermission.granted;
  }

  /// Shows Android's "Allow notifications?" dialog. Returns false if the user
  /// said no (after two refusals Android stops showing the dialog).
  @override
  Future<bool> requestNotifications() async =>
      await _android?.requestNotificationsPermission() ?? true;

  /// Opens the "Alarms & reminders" settings page for this app.
  @override
  Future<void> requestExactAlarms() async {
    await _android?.requestExactAlarmsPermission();
  }

  /// Opens this app's notification settings (when the dialog won't show).
  @override
  Future<void> openSettings() async {
    await _plugin.openAppNotificationSettings();
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  NotificationDetails get _details => NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          // Medication names are health data: hide them on a locked screen.
          visibility: NotificationVisibility.private,
          ticker: 'Medication reminder',
          actions: const [
            AndroidNotificationAction(_takeAction, 'Mark as taken', showsUserInterface: true),
          ],
        ),
      );

  /// Replaces every pending reminder with [reminders]. Reminders already on
  /// screen are left alone (see [cancel]).
  @override
  Future<void> replaceAll(List<PlannedReminder> reminders, {required bool exact}) async {
    if (!_ready) return;
    await _plugin.cancelAllPendingNotifications();
    final mode =
        exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
    final soon = DateTime.now().add(const Duration(seconds: 5));
    for (final r in reminders) {
      if (r.at.isBefore(soon)) continue; // the plugin refuses times in the past
      try {
        await _plugin.zonedSchedule(
          id: r.id,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: _details,
          androidScheduleMode: mode,
          title: r.title,
          body: r.body,
          payload: jsonEncode({'s': r.scheduleId, 't': r.scheduledAt.millisecondsSinceEpoch}),
        );
      } on Object catch (e) {
        // One bad reminder must not stop the others from being scheduled.
        developer.log('Could not schedule ${r.id}', name: 'NotificationService', error: e);
      }
    }
  }

  /// Removes a reminder from the notification tray (e.g. dose already taken).
  @override
  Future<void> cancel(int id) async {
    if (_ready) await _plugin.cancel(id: id);
  }

  /// Removes everything — used on logout.
  @override
  Future<void> cancelAll() async {
    if (_ready) await _plugin.cancelAll();
  }

  /// A sample reminder [delay] from now, to check sound and permissions.
  @override
  Future<void> scheduleTest({required bool exact, Duration delay = const Duration(seconds: 10)}) async {
    if (!_ready) return;
    await _plugin.zonedSchedule(
      id: 1,
      scheduledDate: tz.TZDateTime.now(tz.local).add(delay),
      notificationDetails: _details,
      androidScheduleMode:
          exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      title: 'Test reminder',
      body: 'Reminders are working. This is how a dose alert will look.',
    );
  }

  DoseNotificationTap? _parse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return null; // e.g. the test reminder
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      return DoseNotificationTap(
        scheduleId: data['s'] as String,
        scheduledAt: DateTime.fromMillisecondsSinceEpoch(data['t'] as int),
        markTaken: response.actionId == _takeAction,
      );
    } on Object {
      return null;
    }
  }
}
