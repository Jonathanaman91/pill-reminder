import 'dart:async';

import '../../medications/domain/medication.dart';
import '../domain/dashboard_snapshot.dart';
import '../domain/today_dose.dart';
import 'dashboard_repository.dart';

/// In-memory stand-in for the real repository, so the dashboard can be run
/// and demoed before the backend exists. Turn it on with
/// `flutter run --dart-define=DEMO_DATA=true`.
class DemoDashboardRepository implements DashboardRepository {
  DemoDashboardRepository({this.simulateOffline = false}) {
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _notify(dataChanged: false));
  }

  /// Set to true to preview the offline banner and the queued-changes text.
  final bool simulateOffline;

  final _changes = StreamController<void>.broadcast();
  final _dataChanges = StreamController<void>.broadcast();
  late final Timer _ticker;
  final _logs = <String, ({DoseStatus status, DateTime? takenAt, String? reason})>{};
  DateTime? _lastSyncedAt;
  int _pending = 0;

  // Starts with a sample plan; the form adds, edits and deletes entries.
  final List<Medication> _medications = [
    Medication(id: 'm1', name: 'Metformin', form: DosageForm.tablet, dosageAmount: 500,
        dosageUnit: 'mg', quantity: 1, times: const [ClockTime(8, 0), ClockTime(19, 30)],
        daysMask: WeekDays.everyDay, startDate: _sampleStart, instructions: 'After food'),
    Medication(id: 'm2', name: 'Amlodipine', form: DosageForm.tablet, dosageAmount: 5,
        dosageUnit: 'mg', quantity: 1, times: const [ClockTime(9, 30)],
        daysMask: WeekDays.everyDay, startDate: _sampleStart),
    Medication(id: 'm3', name: 'Vitamin D3', form: DosageForm.capsule, dosageAmount: 1000,
        dosageUnit: 'IU', quantity: 1, times: const [ClockTime(13, 0)],
        daysMask: WeekDays.everyDay, startDate: _sampleStart, instructions: 'With food'),
    Medication(id: 'm4', name: 'Atorvastatin', form: DosageForm.tablet, dosageAmount: 20,
        dosageUnit: 'mg', quantity: 1, times: const [ClockTime(22, 0)],
        daysMask: WeekDays.everyDay, startDate: _sampleStart),
  ];
  static final _sampleStart = DateTime(2026);

  void _notify({bool dataChanged = true}) {
    if (!_changes.isClosed) _changes.add(null);
    if (dataChanged && !_dataChanges.isClosed) _dataChanges.add(null);
  }

  static DateTime _minuteNow() {
    final c = DateTime.now();
    return DateTime(c.year, c.month, c.day, c.hour, c.minute);
  }

  @override
  Stream<void> get changes => _dataChanges.stream;

  @override
  Future<List<TodayDose>> upcomingDoses({int days = 7}) async {
    final now = _minuteNow();
    return [
      for (var i = 0; i < days; i++)
        ..._dosesOn(DateTime(now.year, now.month, now.day + i), now),
    ];
  }

  @override
  Future<TodayDose?> recordDoseAt(String scheduleId, DateTime scheduledAt, DoseStatus status) async {
    for (final dose in _build().doses) {
      if (dose.scheduleId == scheduleId && dose.scheduledAt == scheduledAt) {
        return dose.status.isResolved ? dose : await recordDose(dose, status);
      }
    }
    return null;
  }

  DashboardSnapshot _build() {
    final now = _minuteNow();
    return DashboardSnapshot(
      now: now,
      doses: _dosesOn(DateTime(now.year, now.month, now.day), now),
      streakBeforeToday: 11,
      bestStreak: 19,
      streakAsOf: now,
      lastSyncedAt: _lastSyncedAt,
      pendingSyncCount: _pending,
    );
  }

  /// One day's doses, earliest first, from the medications in memory.
  List<TodayDose> _dosesOn(DateTime day, DateTime now) {
    final dayBit = 1 << (day.weekday - 1); // Mon=1 … Sun=64
    final doses = <TodayDose>[];
    for (final med in _medications) {
      final end = med.endDate;
      if (med.daysMask & dayBit == 0) continue;
      if (day.isBefore(med.startDate) || (end != null && day.isAfter(end))) continue;

      for (final time in med.times) {
        final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
        // The id depends only on the medication and the time, so editing other
        // details keeps today's "taken" marks.
        final scheduleId = '${med.id}-${time.hhmm}';
        final key = '$scheduleId@${at.millisecondsSinceEpoch}';
        final log = _logs[key];
        doses.add(TodayDose(
          scheduleId: scheduleId,
          medicationId: med.id,
          name: med.name,
          dosageAmount: med.dosageAmount,
          dosageUnit: med.dosageUnit,
          form: med.form.name,
          formDetail: med.formDetail,
          quantity: med.quantity,
          instructions: med.instructions,
          photo: med.photo,
          scheduledAt: at,
          status: DosePolicy.resolve(scheduledAt: at, now: now, loggedStatus: log?.status.name),
          logId: log == null ? null : key,
          takenAt: log?.takenAt,
          skipReason: log?.reason,
        ));
      }
    }
    return doses..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  @override
  Stream<DashboardSnapshot> watchToday() async* {
    // Pretend the first database read is slow, so the skeleton is visible.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    yield _build();
    yield* _changes.stream.map((_) => _build());
  }

  @override
  Future<SyncOutcome> sync() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    _lastSyncedAt ??= DateTime.now().subtract(const Duration(minutes: 42));
    if (simulateOffline) {
      _notify();
      return SyncOutcome.offline;
    }
    _pending = 0;
    _lastSyncedAt = DateTime.now();
    _notify();
    return SyncOutcome.synced;
  }

  @override
  Future<TodayDose> recordDose(TodayDose dose, DoseStatus status, {String? skipReason}) async {
    final takenAt = status == DoseStatus.taken ? DateTime.now() : null;
    final reason = status == DoseStatus.skipped ? skipReason : null;
    _logs[dose.key] = (status: status, takenAt: takenAt, reason: reason);
    if (simulateOffline) _pending++;
    _notify();
    return dose.copyWith(status: status, logId: dose.key, takenAt: takenAt, skipReason: () => reason);
  }

  /// Sample history: most doses taken, a few skipped or missed, so the
  /// History tab has something to show in demo mode.
  @override
  Future<List<DoseDay>> history({int days = 30}) async {
    final now = _minuteNow();
    final result = <DoseDay>[];
    for (var i = 1; i <= days; i++) {
      final day = DateTime(now.year, now.month, now.day - i);
      final doses = [
        for (final (n, d) in _dosesOn(day, now).indexed)
          switch ((i * 7 + n * 3) % 17) {
            0 => d.copyWith(status: DoseStatus.skipped, skipReason: () => 'Ran out of medicine'),
            5 => d, // never marked: missed
            _ => d.copyWith(status: DoseStatus.taken, takenAt: d.scheduledAt.add(Duration(minutes: n * 4))),
          },
      ];
      if (doses.isNotEmpty) result.add((day: day, doses: doses));
    }
    return result;
  }

  @override
  Future<void> undoDose(TodayDose dose) async {
    _logs.remove(dose.key);
    if (simulateOffline) _pending++;
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Used by DemoMedicationRepository, so the medication screens work without
  // a backend.
  // ---------------------------------------------------------------------------

  List<Medication> get medications => [..._medications]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  void addMedication(NewMedication med) {
    _medications.add(Medication.fromNew('demo-${DateTime.now().microsecondsSinceEpoch}', med));
    _notify();
  }

  void updateMedication(String id, NewMedication med) {
    final index = _medications.indexWhere((m) => m.id == id);
    if (index < 0) throw StateError('This medication no longer exists.');
    _medications[index] = Medication.fromNew(id, med);
    _notify();
  }

  void deleteMedication(String id) {
    _medications.removeWhere((m) => m.id == id);
    _notify();
  }

  @override
  Future<void> onLocalDataChanged() async => _notify();

  @override
  Future<void> dispose() async {
    _ticker.cancel();
    await _changes.close();
    await _dataChanges.close();
  }
}
