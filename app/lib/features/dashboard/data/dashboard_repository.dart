import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_pusher.dart';
import '../domain/dashboard_snapshot.dart';
import '../domain/today_dose.dart';
import 'dashboard_local_source.dart';
import 'dashboard_remote_source.dart';

enum SyncOutcome { synced, offline, failed }

/// The only thing the DashboardBloc talks to. The BLoC never knows whether
/// data came from SQLite or the API — that is the repository's job.
abstract interface class DashboardRepository {
  /// Emits a fresh snapshot whenever the cache changes, and once a minute so
  /// "due" / "missed" states and relative times stay correct.
  Stream<DashboardSnapshot> watchToday();

  /// Uploads pending changes, then downloads what changed on the server.
  Future<SyncOutcome> sync();

  Future<TodayDose> recordDose(TodayDose dose, DoseStatus status);

  Future<void> undoDose(TodayDose dose);

  /// Another feature (e.g. Add medication) changed the local database:
  /// refresh the dashboard now and upload in the background.
  Future<void> onLocalDataChanged();

  /// Fires when medications, schedules or dose logs change (not on the
  /// once-a-minute clock tick). Reminders reschedule when this fires.
  Stream<void> get changes;

  /// Today's and the coming days' doses, for scheduling reminders.
  Future<List<TodayDose>> upcomingDoses({int days = 7});

  /// Marks a dose found by its slot (used by the notification's
  /// "Mark as taken" button). Returns null if it isn't one of today's doses.
  Future<TodayDose?> recordDoseAt(String scheduleId, DateTime scheduledAt, DoseStatus status);

  Future<void> dispose();
}

/// Offline-first: every read comes from SQLite, every write goes to SQLite
/// first and is uploaded in the background. This answers the group's
/// "Poor Internet Connectivity" constraint — the app never waits on the network
/// to show or update the schedule.
class OfflineFirstDashboardRepository implements DashboardRepository {
  OfflineFirstDashboardRepository({
    required DashboardLocalSource local,
    required DashboardRemoteSource remote,
    List<SyncPusher> pushers = const [],
    DateTime Function()? clock,
  })  : _local = local,
        _remote = remote,
        _pushers = pushers,
        _clock = clock ?? DateTime.now {
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _notify(dataChanged: false));
  }

  final DashboardLocalSource _local;
  final DashboardRemoteSource _remote;
  final List<SyncPusher> _pushers;
  final DateTime Function() _clock;
  final _changes = StreamController<void>.broadcast();
  final _dataChanges = StreamController<void>.broadcast();
  late final Timer _ticker;
  Future<SyncOutcome>? _syncInFlight;
  bool _syncAgain = false;

  void _notify({bool dataChanged = true}) {
    if (!_changes.isClosed) _changes.add(null);
    if (dataChanged && !_dataChanges.isClosed) _dataChanges.add(null);
  }

  @override
  Stream<void> get changes => _dataChanges.stream;

  @override
  Future<List<TodayDose>> upcomingDoses({int days = 7}) =>
      _local.upcomingDoses(_clock(), days: days);

  @override
  Future<TodayDose?> recordDoseAt(String scheduleId, DateTime scheduledAt, DoseStatus status) async {
    final snapshot = await _local.loadSnapshot(_clock());
    for (final dose in snapshot.doses) {
      if (dose.scheduleId == scheduleId && dose.scheduledAt == scheduledAt) {
        return dose.status.isResolved ? dose : await recordDose(dose, status);
      }
    }
    return null;
  }

  @override
  Stream<DashboardSnapshot> watchToday() {
    late final StreamController<DashboardSnapshot> controller;
    StreamSubscription<void>? changeSub;
    var queue = Future<void>.value();

    // Loads run one after another, so snapshots can never arrive out of order.
    void emitLatest() {
      queue = queue.then((_) async {
        try {
          final snapshot = await _local.loadSnapshot(_clock());
          if (!controller.isClosed) controller.add(snapshot);
        } catch (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        }
      });
    }

    controller = StreamController<DashboardSnapshot>(
      onListen: () {
        changeSub = _changes.stream.listen((_) => emitLatest());
        emitLatest();
      },
      onCancel: () async {
        await changeSub?.cancel();
        await controller.close();
      },
    );
    return controller.stream;
  }

  /// Only one sync runs at a time. If a new change arrives while one is
  /// running, it runs once more afterwards so that change is not left behind.
  @override
  Future<SyncOutcome> sync() {
    final running = _syncInFlight;
    if (running != null) {
      _syncAgain = true;
      return running;
    }
    return _syncInFlight = _syncLoop().whenComplete(() => _syncInFlight = null);
  }

  Future<SyncOutcome> _syncLoop() async {
    SyncOutcome outcome;
    do {
      _syncAgain = false;
      outcome = await _runSync();
    } while (_syncAgain && outcome == SyncOutcome.synced);
    return outcome;
  }

  Future<SyncOutcome> _runSync() async {
    try {
      // 1. Push first, so the server's answer already includes our changes.
      //    Medications go before dose logs, which point to them.
      for (final pusher in _pushers) {
        await pusher.pushPending();
      }
      final pending = await _local.pendingDoseLogs();
      if (pending.isNotEmpty) {
        await _remote.pushDoseLogs(pending);
        await _local.markSynced(pending);
      }
      // 2. Pull only what changed since the last successful pull.
      final payload = await _remote.pull(since: await _local.lastPulledAt());
      await _local.applyServerChanges(payload, _clock());
      return SyncOutcome.synced;
    } on DioException catch (e) {
      return e.isOffline ? SyncOutcome.offline : SyncOutcome.failed;
    } catch (e, st) {
      // Bad JSON or a database error: report it instead of crashing the app.
      developer.log('Sync failed', name: 'DashboardRepository', error: e, stackTrace: st);
      return SyncOutcome.failed;
    } finally {
      _notify();
    }
  }

  @override
  Future<TodayDose> recordDose(TodayDose dose, DoseStatus status) async {
    final saved = await _local.saveDoseStatus(dose, status, _clock());
    _notify();
    unawaited(sync()); // best effort; stays queued if offline
    return saved;
  }

  @override
  Future<void> undoDose(TodayDose dose) async {
    final logId = dose.logId;
    if (logId == null) return;
    await _local.clearDoseStatus(logId, _clock());
    _notify();
    unawaited(sync());
  }

  @override
  Future<void> onLocalDataChanged() async {
    _notify();
    unawaited(sync());
  }

  @override
  Future<void> dispose() async {
    _ticker.cancel();
    await _changes.close();
    await _dataChanges.close();
  }
}
