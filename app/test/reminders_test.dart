import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pill_reminder/core/notifications/notification_service.dart';
import 'package:pill_reminder/core/notifications/reminder_planner.dart';
import 'package:pill_reminder/features/dashboard/data/dashboard_repository.dart';
import 'package:pill_reminder/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:pill_reminder/features/dashboard/domain/today_dose.dart';
import 'package:pill_reminder/features/reminders/bloc/reminders_cubit.dart';

TodayDose _dose(String id, DateTime at, [DoseStatus status = DoseStatus.upcoming]) => TodayDose(
      scheduleId: id,
      medicationId: 'm',
      name: 'Metformin',
      dosageAmount: 500,
      dosageUnit: 'mg',
      form: 'tablet',
      quantity: 1,
      scheduledAt: at,
      status: status,
    );

class _FakePlatform implements ReminderPlatform {
  final tapController = StreamController<DoseNotificationTap>.broadcast();
  ReminderPermission current = ReminderPermission.granted;
  List<PlannedReminder> scheduled = [];
  bool? lastExact;
  int replaceCalls = 0;
  final cancelled = <int>{};
  bool cancelledAll = false;

  @override
  Stream<DoseNotificationTap> get taps => tapController.stream;
  @override
  DoseNotificationTap? takeLaunchTap() => null;
  @override
  Future<ReminderPermission> permission() async => current;
  @override
  Future<bool> requestNotifications() async => false;
  @override
  Future<void> requestExactAlarms() async {}
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> replaceAll(List<PlannedReminder> reminders, {required bool exact}) async {
    scheduled = reminders;
    lastExact = exact;
    replaceCalls++;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }
  @override
  Future<void> cancelAll() async {
    cancelledAll = true;
  }
  @override
  Future<void> scheduleTest({required bool exact, Duration delay = const Duration(seconds: 10)}) async {}
}

class _FakeRepo implements DashboardRepository {
  _FakeRepo(this.doses);

  List<TodayDose> doses;
  final changeController = StreamController<void>.broadcast();
  final recorded = <String>[];

  @override
  Stream<void> get changes => changeController.stream;
  @override
  Future<List<TodayDose>> upcomingDoses({int days = 7}) async => doses;
  @override
  Future<TodayDose?> recordDoseAt(String scheduleId, DateTime scheduledAt, DoseStatus status) async {
    recorded.add(scheduleId);
    return doses.firstWhere((d) => d.scheduleId == scheduleId);
  }

  @override
  Stream<DashboardSnapshot> watchToday() => const Stream.empty();
  @override
  Future<SyncOutcome> sync() async => SyncOutcome.synced;
  @override
  Future<TodayDose> recordDose(TodayDose dose, DoseStatus status) async => dose;
  @override
  Future<void> undoDose(TodayDose dose) async {}
  @override
  Future<void> onLocalDataChanged() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  final now = DateTime(2026, 11, 11, 9, 0);

  group('ReminderPlanner', () {
    test('a dose and its follow-up, skipping taken doses and the past', () {
      final plan = ReminderPlanner.plan([
        _dose('past', DateTime(2026, 11, 11, 8, 0)), // follow-up 08:30 also past
        _dose('soon', DateTime(2026, 11, 11, 8, 45)), // only the 09:15 follow-up left
        _dose('later', DateTime(2026, 11, 11, 20, 0)),
        _dose('done', DateTime(2026, 11, 11, 21, 0), DoseStatus.taken),
      ], now);

      expect(plan.map((r) => (r.scheduleId, r.at.hour, r.at.minute)), [
        ('soon', 9, 15),
        ('later', 20, 0),
        ('later', 20, 30),
      ]);
      expect(plan[1].title, 'Time for Metformin');
      expect(plan[0].title, 'Did you take Metformin?');
    });

    test('ids are stable, different for follow-ups, and fit in 31 bits', () {
      final at = DateTime(2026, 11, 11, 8);
      final a = ReminderPlanner.idFor('s1', at, followUp: false);
      expect(ReminderPlanner.idFor('s1', at, followUp: false), a);
      expect(ReminderPlanner.idFor('s1', at, followUp: true), isNot(a));
      expect(ReminderPlanner.idFor('s2', at, followUp: false), isNot(a));
      expect(a, lessThan(1 << 31));
    });

    test('never more than the cap', () {
      final many = [
        for (var i = 0; i < 300; i++) _dose('s$i', now.add(Duration(minutes: 10 + i))),
      ];
      expect(ReminderPlanner.plan(many, now), hasLength(ReminderPlanner.maxReminders));
    });
  });

  group('RemindersCubit', () {
    late _FakePlatform platform;
    late _FakeRepo repo;
    late RemindersCubit cubit;

    setUp(() {
      platform = _FakePlatform();
      repo = _FakeRepo([
        _dose('a', DateTime(2026, 11, 11, 20)),
        _dose('b', DateTime(2026, 11, 11, 8), DoseStatus.taken),
      ]);
      cubit = RemindersCubit(
        platform: platform,
        repository: repo,
        debounce: Duration.zero,
        clock: () => now,
      );
    });
    tearDown(() => cubit.close());

    test('start schedules reminders and clears alerts for taken doses', () async {
      await cubit.start();
      expect(platform.scheduled, hasLength(2)); // 20:00 + 20:30 follow-up
      expect(platform.lastExact, isTrue);
      expect(cubit.state.scheduledCount, 2);
      expect(platform.cancelled,
          contains(ReminderPlanner.idFor('b', DateTime(2026, 11, 11, 8), followUp: false)));
    });

    test('falls back to inexact alarms when "Alarms & reminders" is off', () async {
      platform.current = ReminderPermission.exactAlarmsOff;
      await cubit.start();
      expect(platform.lastExact, isFalse);
      expect(cubit.state.needsAttention, isTrue);
    });

    test('reschedules after a data change, but not when nothing changed', () async {
      await cubit.start();
      final calls = platform.replaceCalls;

      repo.changeController.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(platform.replaceCalls, calls); // same plan → skipped

      repo.doses = [...repo.doses, _dose('c', DateTime(2026, 11, 11, 22))];
      repo.changeController.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(platform.replaceCalls, calls + 1);
      expect(platform.scheduled, hasLength(4));
    });

    test('"Mark as taken" on a notification records the dose', () async {
      await cubit.start();
      platform.tapController.add(DoseNotificationTap(
          scheduleId: 'a', scheduledAt: DateTime(2026, 11, 11, 20), markTaken: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repo.recorded, ['a']);
      expect(cubit.state.notice?.message, 'Metformin marked as taken');
    });

    test('a refused permission is remembered, and logout cancels everything', () async {
      platform.current = ReminderPermission.notificationsOff;
      await cubit.start();
      await cubit.requestPermission();
      expect(cubit.state.notificationsRefused, isTrue);

      await cubit.stop();
      expect(platform.cancelledAll, isTrue);
      expect(cubit.state.active, isFalse);
    });
  });
}
