import 'dart:async';
import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/notifications/reminder_planner.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../dashboard/domain/today_dose.dart';

final class RemindersNotice extends Equatable {
  const RemindersNotice(this.id, this.message);

  final int id;
  final String message;

  @override
  List<Object?> get props => [id];
}

final class RemindersState extends Equatable {
  const RemindersState({
    this.active = false,
    this.permission,
    this.scheduledCount = 0,
    this.notificationsRefused = false,
    this.notice,
  });

  /// True while a user is logged in.
  final bool active;
  final ReminderPermission? permission;

  /// How many reminders (including follow-ups) are waiting for the next 7 days.
  final int scheduledCount;

  /// The user said "Don't allow"; next time, open Settings instead of asking.
  final bool notificationsRefused;
  final RemindersNotice? notice;

  bool get needsAttention =>
      active && permission != null && permission != ReminderPermission.granted;

  RemindersState copyWith({
    bool? active,
    ReminderPermission? permission,
    int? scheduledCount,
    bool? notificationsRefused,
    RemindersNotice? notice,
  }) =>
      RemindersState(
        active: active ?? this.active,
        permission: permission ?? this.permission,
        scheduledCount: scheduledCount ?? this.scheduledCount,
        notificationsRefused: notificationsRefused ?? this.notificationsRefused,
        notice: notice ?? this.notice,
      );

  @override
  List<Object?> get props => [active, permission, scheduledCount, notificationsRefused, notice];
}

/// Keeps the phone's scheduled alarms in step with the medication schedule.
///
///   login  → start(): check permission, schedule the next 7 days
///   any change to medications or doses → reschedule (debounced)
///   dose taken → its tray notification and follow-up are cancelled
///   logout → stop(): cancel everything
///
/// Rescheduling happens every time the app opens or data changes, so the
/// 7-day window keeps rolling forward as long as the app is used weekly.
class RemindersCubit extends Cubit<RemindersState> {
  RemindersCubit({
    required ReminderPlatform platform,
    required DashboardRepository repository,
    Duration debounce = const Duration(milliseconds: 800),
    DateTime Function()? clock,
  })  : _platform = platform,
        _repository = repository,
        _debounceDelay = debounce,
        _clock = clock ?? DateTime.now,
        super(const RemindersState());

  final ReminderPlatform _platform;
  final DashboardRepository _repository;
  final Duration _debounceDelay;
  final DateTime Function() _clock;

  StreamSubscription<void>? _changesSub;
  StreamSubscription<DoseNotificationTap>? _tapsSub;
  Timer? _debounce;
  String? _lastPlan;
  int _noticeSeq = 0;

  static const horizonDays = 7;

  Future<void> start() async {
    if (state.active) return;
    emit(state.copyWith(active: true));
    _changesSub = _repository.changes.listen((_) => _rescheduleSoon());
    _tapsSub = _platform.taps.listen(_handleTap);

    final launchTap = _platform.takeLaunchTap();
    if (launchTap != null) await _handleTap(launchTap);
    await refreshPermission(forceReschedule: true);
  }

  Future<void> stop() async {
    await _changesSub?.cancel();
    await _tapsSub?.cancel();
    _debounce?.cancel();
    _changesSub = null;
    _tapsSub = null;
    _lastPlan = null;
    await _platform.cancelAll();
    if (!isClosed) emit(const RemindersState());
  }

  /// Called on start and whenever the app comes back to the foreground
  /// (the user may have changed permissions in Settings meanwhile).
  Future<void> refreshPermission({bool forceReschedule = false}) async {
    if (!state.active) return;
    final permission = await _platform.permission();
    final changed = permission != state.permission;
    if (isClosed) return;
    emit(state.copyWith(permission: permission));
    if (changed || forceReschedule) await reschedule(force: true);
  }

  /// "Turn on" in the banner.
  Future<void> requestPermission() async {
    switch (state.permission) {
      case ReminderPermission.notificationsOff:
        if (state.notificationsRefused) {
          await _platform.openSettings(); // the system dialog won't show again
        } else if (!await _platform.requestNotifications()) {
          emit(state.copyWith(notificationsRefused: true));
        }
      case ReminderPermission.exactAlarmsOff:
        await _platform.requestExactAlarms();
      case ReminderPermission.granted:
      case null:
        break;
    }
    await refreshPermission();
  }

  Future<void> sendTestReminder() async {
    if (state.permission == ReminderPermission.notificationsOff) {
      return _notify('Turn on notifications first, then try again.');
    }
    await _platform.scheduleTest(exact: state.permission != ReminderPermission.exactAlarmsOff);
    _notify('A test reminder will appear in about 10 seconds. You can close the app.');
  }

  void _rescheduleSoon() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, reschedule);
  }

  Future<void> reschedule({bool force = false}) async {
    if (!state.active || isClosed) return;
    try {
      final doses = await _repository.upcomingDoses(days: horizonDays);
      final plan = ReminderPlanner.plan(doses, _clock());
      final exact = state.permission != ReminderPermission.exactAlarmsOff;

      // A dose taken in the app clears its alert from the notification tray.
      for (final d in doses.where((d) => d.status.isResolved)) {
        await _platform.cancel(ReminderPlanner.idFor(d.scheduleId, d.scheduledAt, followUp: false));
        await _platform.cancel(ReminderPlanner.idFor(d.scheduleId, d.scheduledAt, followUp: true));
      }

      // Skip the (slow) platform calls when nothing actually changed.
      final signature = '$exact|${plan.join(',')}';
      if (!force && signature == _lastPlan) return;
      _lastPlan = signature;

      await _platform.replaceAll(plan, exact: exact);
      if (!isClosed) emit(state.copyWith(scheduledCount: plan.length));
    } catch (e, st) {
      // Reminders are best effort: never crash the app over them.
      developer.log('Rescheduling failed', name: 'RemindersCubit', error: e, stackTrace: st);
    }
  }

  Future<void> _handleTap(DoseNotificationTap tap) async {
    if (!tap.markTaken) return; // a plain tap just opens the dashboard
    final dose = await _repository.recordDoseAt(tap.scheduleId, tap.scheduledAt, DoseStatus.taken);
    _notify(dose == null
        ? 'That reminder was for an earlier day, so nothing was changed.'
        : '${dose.name} marked as taken');
  }

  void _notify(String message) {
    if (!isClosed) emit(state.copyWith(notice: RemindersNotice(++_noticeSeq, message)));
  }

  @override
  Future<void> close() async {
    await _changesSub?.cancel();
    await _tapsSub?.cancel();
    _debounce?.cancel();
    return super.close();
  }
}
