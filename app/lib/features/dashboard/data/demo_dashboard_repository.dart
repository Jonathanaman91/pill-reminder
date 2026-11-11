import 'dart:async';

import '../../medications/domain/medication.dart';
import '../domain/dashboard_snapshot.dart';
import '../domain/today_dose.dart';
import 'dashboard_repository.dart';

typedef _Slot = ({
  String id,
  String med,
  String name,
  double amount,
  String unit,
  String form,
  double qty,
  String? note,
  int h,
  int m,
  String? photo,
  int days,
});

/// In-memory stand-in for the real repository, so the dashboard can be run
/// and demoed before the backend exists. Turn it off with
/// `flutter run --dart-define=DEMO_DATA=false`.
class DemoDashboardRepository implements DashboardRepository {
  DemoDashboardRepository({this.simulateOffline = false}) {
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _notify(dataChanged: false));
  }

  /// Set to true to preview the offline banner and the queued-changes text.
  final bool simulateOffline;

  final _changes = StreamController<void>.broadcast();
  final _dataChanges = StreamController<void>.broadcast();
  late final Timer _ticker;
  final _logs = <String, ({DoseStatus status, DateTime? takenAt})>{};
  DateTime? _lastSyncedAt;
  int _pending = 0;

  // Starts with a sample plan; medications added in the form are appended.
  final List<_Slot> _plan = [..._samplePlan];

  static const List<_Slot> _samplePlan = [
    (id: 's1', med: 'm1', name: 'Metformin', amount: 500.0, unit: 'mg', form: 'tablet',
        qty: 1.0, note: 'After breakfast', h: 8, m: 0, photo: null, days: 127),
    (id: 's2', med: 'm2', name: 'Amlodipine', amount: 5.0, unit: 'mg', form: 'tablet',
        qty: 1.0, note: null, h: 9, m: 30, photo: null, days: 127),
    (id: 's3', med: 'm3', name: 'Vitamin D3', amount: 1000.0, unit: 'IU', form: 'capsule',
        qty: 1.0, note: 'With food', h: 13, m: 0, photo: null, days: 127),
    (id: 's4', med: 'm1', name: 'Metformin', amount: 500.0, unit: 'mg', form: 'tablet',
        qty: 1.0, note: 'After dinner', h: 19, m: 30, photo: null, days: 127),
    (id: 's5', med: 'm4', name: 'Atorvastatin', amount: 20.0, unit: 'mg', form: 'tablet',
        qty: 1.0, note: null, h: 22, m: 0, photo: null, days: 127),
  ];

  void _notify({bool dataChanged = true}) {
    if (!_changes.isClosed) _changes.add(null);
    if (dataChanged && !_dataChanges.isClosed) _dataChanges.add(null);
  }

  @override
  Stream<void> get changes => _dataChanges.stream;

  @override
  Future<List<TodayDose>> upcomingDoses({int days = 7}) async {
    final c = DateTime.now();
    final now = DateTime(c.year, c.month, c.day, c.hour, c.minute);
    return [
      for (var i = 0; i < days; i++)
        for (final slot in _plan)
          if (slot.days & (1 << (DateTime(now.year, now.month, now.day + i).weekday - 1)) != 0)
            _doseFor(slot, now, day: DateTime(now.year, now.month, now.day + i)),
    ]..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
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
    final c = DateTime.now();
    final now = DateTime(c.year, c.month, c.day, c.hour, c.minute);
    final todayBit = 1 << (now.weekday - 1);
    final doses = [
      for (final slot in _plan)
        if (slot.days & todayBit != 0) _doseFor(slot, now),
    ]..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return DashboardSnapshot(
      now: now,
      doses: doses,
      streakBeforeToday: 11,
      bestStreak: 19,
      streakAsOf: now,
      lastSyncedAt: _lastSyncedAt,
      pendingSyncCount: _pending,
    );
  }

  TodayDose _doseFor(_Slot p, DateTime now, {DateTime? day}) {
    final d = day ?? now;
    final at = DateTime(d.year, d.month, d.day, p.h, p.m);
    final key = '${p.id}@${at.millisecondsSinceEpoch}';
    final log = _logs[key];
    return TodayDose(
      scheduleId: p.id,
      medicationId: p.med,
      name: p.name,
      dosageAmount: p.amount,
      dosageUnit: p.unit,
      form: p.form,
      quantity: p.qty,
      instructions: p.note,
      photo: p.photo,
      scheduledAt: at,
      status: DosePolicy.resolve(scheduledAt: at, now: now, loggedStatus: log?.status.name),
      logId: log == null ? null : key,
      takenAt: log?.takenAt,
    );
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
  Future<TodayDose> recordDose(TodayDose dose, DoseStatus status) async {
    final takenAt = status == DoseStatus.taken ? DateTime.now() : null;
    _logs[dose.key] = (status: status, takenAt: takenAt);
    if (simulateOffline) _pending++;
    _notify();
    return dose.copyWith(status: status, logId: dose.key, takenAt: takenAt);
  }

  @override
  Future<void> undoDose(TodayDose dose) async {
    _logs.remove(dose.key);
    if (simulateOffline) _pending++;
    _notify();
  }

  /// Used by DemoMedicationRepository so the Add Medication form works
  /// without a backend.
  void addMedication(NewMedication med) {
    final id = 'demo-${DateTime.now().microsecondsSinceEpoch}';
    for (final (i, t) in med.times.indexed) {
      _plan.add((
        id: '$id-$i',
        med: id,
        name: med.name.trim(),
        amount: med.dosageAmount,
        unit: med.dosageUnit,
        form: med.form.name,
        qty: med.quantity,
        note: med.instructions,
        h: t.hour,
        m: t.minute,
        photo: med.photoPath,
        days: med.daysMask,
      ));
    }
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
