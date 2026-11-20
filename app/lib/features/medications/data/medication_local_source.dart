import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/medication.dart';

/// Saves medications to SQLite with sync_state = 'pending'. They show on the
/// dashboard at once and are uploaded by [MedicationSyncPusher] later.
///
/// Edits and deletes work the same way: the row is changed on the phone first
/// and marked 'pending'. A deleted row stays in the table (deleted = 1,
/// hidden from every screen) until the server has been told, then it is removed.
class MedicationLocalSource {
  MedicationLocalSource(AppDatabase database, {Uuid? uuid})
      : _db = database.db,
        _uuid = uuid ?? const Uuid();

  final Database _db;
  final Uuid _uuid;
  static final _day = DateFormat('yyyy-MM-dd');

  // ---------------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------------

  /// Every medication saved on this phone, A to Z.
  Future<List<Medication>> all() async {
    final meds = await _db.query('medications',
        where: 'deleted = 0', orderBy: 'name COLLATE NOCASE');
    final schedules =
        await _db.query('schedules', where: 'deleted = 0', orderBy: 'time_of_day');

    final byMedication = <String, List<Map<String, Object?>>>{};
    for (final s in schedules) {
      (byMedication[s['medication_id'] as String] ??= []).add(s);
    }
    return [
      for (final m in meds) _toMedication(m, byMedication[m['id']] ?? const []),
    ];
  }

  Medication _toMedication(Map<String, Object?> m, List<Map<String, Object?>> schedules) {
    final times = <ClockTime>{
      for (final s in schedules) _parseTime(s['time_of_day'] as String),
    }.toList()
      ..sort();
    // The form has one "days" and one "each dose" choice for all times.
    final first = schedules.isEmpty ? null : schedules.first;

    return Medication(
      id: m['id'] as String,
      name: m['name'] as String,
      form: DosageForm.values.firstWhere((f) => f.name == m['form'],
          orElse: () => DosageForm.other),
      dosageAmount: (m['dosage_amount'] as num).toDouble(),
      dosageUnit: m['dosage_unit'] as String,
      quantity: (first?['quantity'] as num?)?.toDouble() ?? 1,
      times: times,
      daysMask: first?['days_mask'] as int? ?? WeekDays.everyDay,
      startDate: _day.parse(m['start_date'] as String),
      endDate: m['end_date'] == null ? null : _day.parse(m['end_date'] as String),
      instructions: m['instructions'] as String?,
      formDetail: m['form_detail'] as String?,
      photo: (m['local_photo_path'] ?? m['photo_path']) as String?,
    );
  }

  static ClockTime _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return ClockTime(int.parse(parts[0]), int.parse(parts[1]));
  }

  // ---------------------------------------------------------------------------
  // Writing
  // ---------------------------------------------------------------------------

  Future<String> insert(NewMedication med, DateTime now) async {
    final id = _uuid.v4();
    final photo = med.photoPath == null ? null : await _keepPhoto(med.photoPath!, id);
    final stamp = now.toUtc().toIso8601String();

    await _db.transaction((txn) async {
      await txn.insert('medications', {
        'id': id,
        ..._columns(med),
        'local_photo_path': photo,
        'is_active': 1,
        'updated_at': stamp,
        'sync_state': 'pending',
      });
      for (final time in med.times) {
        await txn.insert('schedules', _newSchedule(id, time.hhmm, med, stamp));
      }
    });
    return id;
  }

  /// Saves an edit. A reminder time that is still in the list keeps its
  /// schedule row (and so today's "taken" mark); a removed time is marked
  /// deleted; a new time gets a new row.
  Future<void> update(String id, NewMedication med, DateTime now) async {
    final rows = await _db.query('medications',
        where: 'id = ? AND deleted = 0', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw StateError('This medication no longer exists.');
    final current = rows.first;

    // The form hands back the photo it was showing. Only a different path
    // means the user picked a new one.
    final shown = current['local_photo_path'] ?? current['photo_path'];
    final oldLocal = current['local_photo_path'] as String?;
    final newPhoto = med.photoPath != null && med.photoPath != shown
        ? await _keepPhoto(med.photoPath!, id, version: now.millisecondsSinceEpoch)
        : null;
    final stamp = now.toUtc().toIso8601String();

    await _db.transaction((txn) async {
      await txn.update(
        'medications',
        {
          ..._columns(med),
          // photo_path = NULL makes the next sync upload the new photo.
          if (newPhoto != null) ...{'local_photo_path': newPhoto, 'photo_path': null},
          'updated_at': stamp,
          'sync_state': 'pending',
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      final wanted = {for (final t in med.times) t.hhmm};
      final kept = <String>{};
      final existing =
          await txn.query('schedules', where: 'medication_id = ?', whereArgs: [id]);
      for (final s in existing) {
        final time = s['time_of_day'] as String;
        final keep = wanted.contains(time) && kept.add(time);
        await txn.update(
          'schedules',
          {
            'days_mask': med.daysMask,
            'quantity': med.quantity,
            'deleted': keep ? 0 : 1,
            'updated_at': stamp,
            'sync_state': 'pending',
          },
          where: 'id = ?',
          whereArgs: [s['id']],
        );
      }
      for (final time in wanted.difference(kept)) {
        await txn.insert('schedules', _newSchedule(id, time, med, stamp));
      }
    });

    if (newPhoto != null && oldLocal != null && oldLocal != newPhoto) {
      await _deleteFile(oldLocal);
    }
  }

  /// Hides the medication and its reminder times now; the rows are removed
  /// for good once the server has been told (see [markUploaded]).
  Future<void> softDelete(String id, DateTime now) async {
    final change = {
      'deleted': 1,
      'updated_at': now.toUtc().toIso8601String(),
      'sync_state': 'pending',
    };
    await _db.transaction((txn) async {
      await txn.update('medications', change, where: 'id = ?', whereArgs: [id]);
      await txn.update('schedules', change, where: 'medication_id = ?', whereArgs: [id]);
    });
  }

  Map<String, Object?> _columns(NewMedication med) => {
        'name': med.name.trim(),
        'dosage_amount': med.dosageAmount,
        'dosage_unit': med.dosageUnit,
        'form': med.form.name,
        'form_detail': med.form == DosageForm.other ? med.formDetail?.trim() : null,
        'instructions': med.instructions,
        'start_date': _day.format(med.startDate),
        'end_date': med.endDate == null ? null : _day.format(med.endDate!),
      };

  Map<String, Object?> _newSchedule(String medicationId, String hhmm, NewMedication med, String stamp) => {
        'id': _uuid.v4(),
        'medication_id': medicationId,
        'time_of_day': hhmm,
        'days_mask': med.daysMask,
        'quantity': med.quantity,
        'updated_at': stamp,
        'sync_state': 'pending',
      };

  /// The camera/gallery gives a temporary file that Android may delete, so
  /// copy it into the app's own documents folder. A replacement photo gets a
  /// new file name ([version]), otherwise Flutter would keep showing the old
  /// picture it has cached under the same path.
  Future<String> _keepPhoto(String sourcePath, String medicationId, {int? version}) async {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'medication_photos'));
    await dir.create(recursive: true);
    final ext = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final name = version == null ? medicationId : '$medicationId-$version';
    final target = p.join(dir.path, '$name$ext');
    await File(sourcePath).copy(target);
    return target;
  }

  /// Tidying up must never fail a save, so errors are ignored here.
  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Left behind; harmless.
    }
  }

  // ---------------------------------------------------------------------------
  // Sync helpers
  // ---------------------------------------------------------------------------

  /// Pending medications in the shape POST /medications/batch expects,
  /// including deleted ones, so the server removes them too.
  Future<List<Map<String, Object?>>> pendingForUpload() async {
    final meds = await _db.query('medications', where: "sync_state = 'pending'");
    final result = <Map<String, Object?>>[];
    for (final m in meds) {
      final schedules = await _db.query('schedules',
          where: 'medication_id = ?', whereArgs: [m['id']], orderBy: 'time_of_day');
      result.add({
        'id': m['id'],
        'name': m['name'],
        'dosageAmount': m['dosage_amount'],
        'dosageUnit': m['dosage_unit'],
        'form': m['form'],
        'formDetail': m['form_detail'],
        'instructions': m['instructions'],
        'startDate': m['start_date'],
        'endDate': m['end_date'],
        'isActive': m['is_active'] == 1,
        'deleted': m['deleted'] == 1,
        'updatedAt': m['updated_at'], // used by markUploaded, not by the server
        'schedules': [
          for (final s in schedules)
            {
              'id': s['id'],
              'timeOfDay': s['time_of_day'],
              'daysMask': s['days_mask'],
              'quantity': s['quantity'],
              'deleted': s['deleted'] == 1,
            },
        ],
      });
    }
    return result;
  }

  /// Marks rows as synced, unless the user edited them during the upload.
  /// Rows that were deleted on this phone are now safe to remove for good.
  Future<void> markUploaded(List<Map<String, Object?>> uploaded) async {
    final batch = _db.batch();
    for (final m in uploaded) {
      batch.update('medications', {'sync_state': 'synced'},
          where: 'id = ? AND updated_at = ?', whereArgs: [m['id'], m['updatedAt']]);
      batch.update('schedules', {'sync_state': 'synced'},
          where: 'medication_id = ? AND updated_at <= ?', whereArgs: [m['id'], m['updatedAt']]);
    }
    await batch.commit(noResult: true);

    const uploadedDelete = "deleted = 1 AND sync_state = 'synced'";
    final gone = await _db.query('medications',
        columns: ['local_photo_path'], where: '$uploadedDelete AND local_photo_path IS NOT NULL');
    await _db.delete('schedules', where: uploadedDelete);
    await _db.delete('medications', where: uploadedDelete);
    for (final row in gone) {
      await _deleteFile(row['local_photo_path'] as String);
    }
  }

  /// Synced medications whose photo is on the phone but not on the server yet.
  Future<List<({String id, String path})>> photosToUpload() async {
    final rows = await _db.query('medications',
        columns: ['id', 'local_photo_path'],
        where: "sync_state = 'synced' AND deleted = 0 "
            'AND local_photo_path IS NOT NULL AND photo_path IS NULL');
    return [
      for (final r in rows)
        if (File(r['local_photo_path'] as String).existsSync())
          (id: r['id'] as String, path: r['local_photo_path'] as String),
    ];
  }

  Future<void> setRemotePhoto(String medicationId, String url) => _db.update(
      'medications', {'photo_path': url}, where: 'id = ?', whereArgs: [medicationId]);
}
