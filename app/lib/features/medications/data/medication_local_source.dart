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
class MedicationLocalSource {
  MedicationLocalSource(AppDatabase database, {Uuid? uuid})
      : _db = database.db,
        _uuid = uuid ?? const Uuid();

  final Database _db;
  final Uuid _uuid;
  static final _day = DateFormat('yyyy-MM-dd');

  Future<String> insert(NewMedication med, DateTime now) async {
    final id = _uuid.v4();
    final photo = med.photoPath == null ? null : await _keepPhoto(med.photoPath!, id);
    final stamp = now.toUtc().toIso8601String();

    await _db.transaction((txn) async {
      await txn.insert('medications', {
        'id': id,
        'name': med.name.trim(),
        'dosage_amount': med.dosageAmount,
        'dosage_unit': med.dosageUnit,
        'form': med.form.name,
        'instructions': med.instructions,
        'local_photo_path': photo,
        'start_date': _day.format(med.startDate),
        'end_date': med.endDate == null ? null : _day.format(med.endDate!),
        'is_active': 1,
        'updated_at': stamp,
        'sync_state': 'pending',
      });
      for (final time in med.times) {
        await txn.insert('schedules', {
          'id': _uuid.v4(),
          'medication_id': id,
          'time_of_day': time.hhmm,
          'days_mask': med.daysMask,
          'quantity': med.quantity,
          'updated_at': stamp,
          'sync_state': 'pending',
        });
      }
    });
    return id;
  }

  /// The camera/gallery gives a temporary file that Android may delete, so
  /// copy it into the app's own documents folder.
  Future<String> _keepPhoto(String sourcePath, String medicationId) async {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'medication_photos'));
    await dir.create(recursive: true);
    final ext = p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final target = p.join(dir.path, '$medicationId$ext');
    await File(sourcePath).copy(target);
    return target;
  }

  // ---------------------------------------------------------------------------
  // Sync helpers
  // ---------------------------------------------------------------------------

  /// Pending medications in the shape POST /medications/batch expects.
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
        'instructions': m['instructions'],
        'startDate': m['start_date'],
        'endDate': m['end_date'],
        'isActive': m['is_active'] == 1,
        'updatedAt': m['updated_at'], // used by markUploaded, not by the server
        'schedules': [
          for (final s in schedules)
            {
              'id': s['id'],
              'timeOfDay': s['time_of_day'],
              'daysMask': s['days_mask'],
              'quantity': s['quantity'],
            },
        ],
      });
    }
    return result;
  }

  /// Marks rows as synced, unless the user edited them during the upload.
  Future<void> markUploaded(List<Map<String, Object?>> uploaded) async {
    final batch = _db.batch();
    for (final m in uploaded) {
      batch.update('medications', {'sync_state': 'synced'},
          where: 'id = ? AND updated_at = ?', whereArgs: [m['id'], m['updatedAt']]);
      batch.update('schedules', {'sync_state': 'synced'},
          where: 'medication_id = ? AND updated_at <= ?', whereArgs: [m['id'], m['updatedAt']]);
    }
    await batch.commit(noResult: true);
  }

  /// Synced medications whose photo is on the phone but not on the server yet.
  Future<List<({String id, String path})>> photosToUpload() async {
    final rows = await _db.query('medications',
        columns: ['id', 'local_photo_path'],
        where: "sync_state = 'synced' AND local_photo_path IS NOT NULL AND photo_path IS NULL");
    return [
      for (final r in rows)
        if (File(r['local_photo_path'] as String).existsSync())
          (id: r['id'] as String, path: r['local_photo_path'] as String),
    ];
  }

  Future<void> setRemotePhoto(String medicationId, String url) => _db.update(
      'medications', {'photo_path': url}, where: 'id = ?', whereArgs: [medicationId]);
}
