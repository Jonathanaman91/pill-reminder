import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/dashboard_snapshot.dart';
import '../domain/today_dose.dart';
import 'dashboard_remote_source.dart';

/// Reads and writes the SQLite cache. Today's list is generated from the
/// cached medications + schedules, so it is correct even on a day the phone
/// never reached the server.
class DashboardLocalSource {
  DashboardLocalSource(AppDatabase database, {Uuid? uuid})
      : _db = database.db,
        _uuid = uuid ?? const Uuid();

  final Database _db;
  final Uuid _uuid;

  static final _day = DateFormat('yyyy-MM-dd');

  // Meta keys
  static const _kLastPulledAt = 'last_pulled_at'; // server clock, ISO-8601
  static const _kLastSyncedAt = 'last_synced_at'; // phone clock, epoch ms
  static const _kStreakBefore = 'streak_before_today';
  static const _kStreakBest = 'streak_best';
  static const _kStreakAsOf = 'streak_as_of';

  // ---------------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------------

  Future<DashboardSnapshot> loadSnapshot(DateTime clock) async {
    final now = DateTime(clock.year, clock.month, clock.day, clock.hour, clock.minute);
    final doses = await _dosesForDay(DateTime(now.year, now.month, now.day), now);

    final meta = await _readMeta();
    final pending = Sqflite.firstIntValue(await _db
            .rawQuery("SELECT COUNT(*) FROM dose_logs WHERE sync_state = 'pending'")) ??
        0;
    final lastSyncedMs = int.tryParse(meta[_kLastSyncedAt] ?? '');

    return DashboardSnapshot(
      now: now,
      doses: doses,
      streakBeforeToday: int.tryParse(meta[_kStreakBefore] ?? '') ?? 0,
      bestStreak: int.tryParse(meta[_kStreakBest] ?? '') ?? 0,
      streakAsOf: DateTime.tryParse(meta[_kStreakAsOf] ?? ''),
      lastSyncedAt:
          lastSyncedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastSyncedMs),
      pendingSyncCount: pending,
    );
  }

  /// Doses for today and the next [days] − 1 days, for scheduling reminders.
  Future<List<TodayDose>> upcomingDoses(DateTime now, {int days = 7}) async {
    final result = <TodayDose>[];
    for (var i = 0; i < days; i++) {
      result.addAll(await _dosesForDay(DateTime(now.year, now.month, now.day + i), now));
    }
    return result;
  }

  /// Builds one day's dose list from the cached medications and schedules,
  /// plus any dose logs already saved for that day.
  Future<List<TodayDose>> _dosesForDay(DateTime dayStart, DateTime now) async {
    final dayEnd = DateTime(dayStart.year, dayStart.month, dayStart.day + 1);
    final day = _day.format(dayStart);
    final weekdayBit = 1 << (dayStart.weekday - 1); // Mon=1 … Sun=64

    final slots = await _db.rawQuery('''
      SELECT s.id AS schedule_id, s.time_of_day, s.quantity,
             m.id AS medication_id, m.name, m.dosage_amount, m.dosage_unit,
             m.form, m.instructions,
             COALESCE(m.local_photo_path, m.photo_path) AS photo
      FROM schedules s
      JOIN medications m ON m.id = s.medication_id
      WHERE m.is_active = 1
        AND m.start_date <= ?
        AND (m.end_date IS NULL OR m.end_date >= ?)
        AND (s.days_mask & ?) != 0
      ORDER BY s.time_of_day, m.name
    ''', [day, day, weekdayBit]);

    final logs = await _db.query(
      'dose_logs',
      where: 'scheduled_at >= ? AND scheduled_at < ? AND deleted = 0',
      whereArgs: [dayStart.millisecondsSinceEpoch, dayEnd.millisecondsSinceEpoch],
    );
    final logBySlot = {
      for (final l in logs) '${l['schedule_id']}@${l['scheduled_at']}': l,
    };

    final doses = <TodayDose>[];
    for (final row in slots) {
      final parts = (row['time_of_day'] as String).split(':');
      final scheduledAt = DateTime(
          dayStart.year, dayStart.month, dayStart.day, int.parse(parts[0]), int.parse(parts[1]));
      final log = logBySlot['${row['schedule_id']}@${scheduledAt.millisecondsSinceEpoch}'];
      final takenAtMs = log?['taken_at'] as int?;

      doses.add(TodayDose(
        scheduleId: row['schedule_id'] as String,
        medicationId: row['medication_id'] as String,
        name: row['name'] as String,
        dosageAmount: (row['dosage_amount'] as num).toDouble(),
        dosageUnit: row['dosage_unit'] as String,
        form: row['form'] as String,
        quantity: (row['quantity'] as num).toDouble(),
        instructions: row['instructions'] as String?,
        photo: row['photo'] as String?,
        scheduledAt: scheduledAt,
        status: DosePolicy.resolve(
          scheduledAt: scheduledAt,
          now: now,
          loggedStatus: log?['status'] as String?,
        ),
        logId: log?['id'] as String?,
        takenAt: takenAtMs == null ? null : DateTime.fromMillisecondsSinceEpoch(takenAtMs),
      ));
    }
    return doses;
  }

  // ---------------------------------------------------------------------------
  // Writing (user actions) — saved locally first, uploaded later.
  // ---------------------------------------------------------------------------

  Future<TodayDose> saveDoseStatus(TodayDose dose, DoseStatus status, DateTime now) async {
    // Re-use the id of an earlier (possibly undone) log for this slot, so the
    // server sees one row being updated instead of two competing rows.
    final existing = await _db.query(
      'dose_logs',
      columns: ['id'],
      where: 'schedule_id = ? AND scheduled_at = ?',
      whereArgs: [dose.scheduleId, dose.scheduledAt.millisecondsSinceEpoch],
      limit: 1,
    );
    final id = existing.isEmpty ? _uuid.v4() : existing.first['id'] as String;
    final takenAt = status == DoseStatus.taken ? now : null;

    await _db.insert(
      'dose_logs',
      {
        'id': id,
        'schedule_id': dose.scheduleId,
        'medication_id': dose.medicationId,
        'scheduled_at': dose.scheduledAt.millisecondsSinceEpoch,
        'status': status.name,
        'taken_at': takenAt?.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
        'deleted': 0,
        'sync_state': 'pending',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return dose.copyWith(status: status, logId: id, takenAt: takenAt);
  }

  Future<void> clearDoseStatus(String logId, DateTime now) => _db.update(
        'dose_logs',
        {'deleted': 1, 'sync_state': 'pending', 'updated_at': now.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [logId],
      );

  // ---------------------------------------------------------------------------
  // Sync helpers
  // ---------------------------------------------------------------------------

  Future<List<Map<String, Object?>>> pendingDoseLogs() =>
      _db.query('dose_logs', where: "sync_state = 'pending'", orderBy: 'updated_at');

  /// Marks uploaded rows as synced — but only if the user has not changed
  /// them again while the upload was running (same updated_at).
  Future<void> markSynced(List<Map<String, Object?>> uploaded) async {
    final batch = _db.batch();
    for (final row in uploaded) {
      batch.update(
        'dose_logs',
        {'sync_state': 'synced'},
        where: 'id = ? AND updated_at = ?',
        whereArgs: [row['id'], row['updated_at']],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<String?> lastPulledAt() async => (await _readMeta())[_kLastPulledAt];

  Future<void> applyServerChanges(SyncPayload payload, DateTime now) async {
    Future<Set<String>> pendingIn(String table) async => {
          for (final r in await _db.query(table, columns: ['id'], where: "sync_state = 'pending'"))
            r['id'] as String,
        };
    // Rows changed on this phone but not uploaded yet: the local copy wins.
    final pendingIds = await pendingIn('dose_logs');
    final pendingMeds = await pendingIn('medications');
    final pendingSchedules = await pendingIn('schedules');
    // REPLACE rewrites the whole row, so remember each photo kept on the phone.
    final localPhotos = {
      for (final r in await _db.query('medications',
          columns: ['id', 'local_photo_path'], where: 'local_photo_path IS NOT NULL'))
        r['id'] as String: r['local_photo_path'] as String,
    };

    await _db.transaction((txn) async {
      final batch = txn.batch();

      for (final m in payload.medications) {
        if (pendingMeds.contains(m['id'])) continue;
        if (m['deletedAt'] != null) {
          batch.delete('medications', where: 'id = ?', whereArgs: [m['id']]);
          batch.delete('schedules', where: 'medication_id = ?', whereArgs: [m['id']]);
          continue;
        }
        batch.insert(
          'medications',
          {
            'id': m['id'],
            'name': m['name'],
            'dosage_amount': _toDouble(m['dosageAmount']),
            'dosage_unit': m['dosageUnit'],
            'form': m['form'],
            'instructions': m['instructions'],
            'photo_path': m['photoUrl'],
            'local_photo_path': localPhotos[m['id']],
            'start_date': (m['startDate'] as String).substring(0, 10),
            'end_date': (m['endDate'] as String?)?.substring(0, 10),
            'is_active': m['isActive'] == false ? 0 : 1,
            'updated_at': m['updatedAt'],
            'sync_state': 'synced',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      for (final s in payload.schedules) {
        if (pendingSchedules.contains(s['id'])) continue;
        if (s['deletedAt'] != null) {
          batch.delete('schedules', where: 'id = ?', whereArgs: [s['id']]);
          continue;
        }
        batch.insert(
          'schedules',
          {
            'id': s['id'],
            'medication_id': s['userMedicationId'],
            'time_of_day': (s['timeOfDay'] as String).substring(0, 5), // "08:00:00" → "08:00"
            'days_mask': s['daysMask'],
            'quantity': _toDouble(s['quantity']),
            'updated_at': s['updatedAt'],
            'sync_state': 'synced',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      for (final l in payload.doseLogs) {
        // A local change that has not been uploaded yet wins over the server copy.
        if (pendingIds.contains(l['id'])) continue;
        final takenAt = l['takenAt'] as String?;
        batch.insert(
          'dose_logs',
          {
            'id': l['id'],
            'schedule_id': l['scheduleId'],
            'medication_id': l['userMedicationId'],
            'scheduled_at': DateTime.parse(l['scheduledAt'] as String).millisecondsSinceEpoch,
            'status': l['status'],
            'taken_at': takenAt == null ? null : DateTime.parse(takenAt).millisecondsSinceEpoch,
            'updated_at': DateTime.parse(l['updatedAt'] as String).millisecondsSinceEpoch,
            'deleted': l['deletedAt'] == null ? 0 : 1,
            'sync_state': 'synced',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      void putMeta(String key, Object? value) => batch.insert(
            'meta',
            {'key': key, 'value': value?.toString()},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
      putMeta(_kLastPulledAt, payload.serverTime);
      putMeta(_kLastSyncedAt, now.millisecondsSinceEpoch);
      putMeta(_kStreakBefore, payload.streakBeforeToday);
      putMeta(_kStreakBest, payload.bestStreak);
      putMeta(_kStreakAsOf, payload.streakAsOf);

      await batch.commit(noResult: true);
    });
  }

  Future<Map<String, String?>> _readMeta() async {
    final rows = await _db.query('meta');
    return {for (final r in rows) r['key'] as String: r['value'] as String?};
  }

  // node-postgres returns NUMERIC columns as strings, so accept both.
  static double _toDouble(Object? v) => v is num ? v.toDouble() : double.parse('$v');
}
