import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local SQLite cache (Feature e). It mirrors the server tables the phone
/// needs, so today's schedule can be BUILT on the device even with no signal,
/// instead of only replaying the last API response.
///
/// No foreign keys on purpose: sync writes rows with REPLACE, and on older
/// Android versions REPLACE = DELETE + INSERT, which would cascade-delete
/// child rows. Deletions arrive from the server explicitly instead.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const _name = 'pill_reminder.db';
  // v2: medications.local_photo_path (photo kept on the phone until uploaded)
  static const _version = 2;

  static Future<AppDatabase> open() async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, _name),
      version: _version,
      onCreate: _create,
      onUpgrade: _upgrade,
    );
    return AppDatabase._(db);
  }

  /// Called on logout, so the next person to log in on this phone does not
  /// see the previous user's medications.
  Future<void> clearAll() async {
    final batch = db.batch()
      ..delete('dose_logs')
      ..delete('schedules')
      ..delete('medications')
      ..delete('meta');
    await batch.commit(noResult: true);
  }

  /// Runs on phones that already have an older database, so nobody has to
  /// uninstall the app to get the new column.
  static Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE medications ADD COLUMN local_photo_path TEXT');
    }
  }

  static Future<void> _create(Database db, int version) async {
    final batch = db.batch()
      ..execute('''
        CREATE TABLE medications (
          id             TEXT PRIMARY KEY,
          name           TEXT NOT NULL,
          dosage_amount  REAL NOT NULL,
          dosage_unit    TEXT NOT NULL,
          form           TEXT NOT NULL,
          instructions   TEXT,
          photo_path     TEXT,                   -- server URL once uploaded
          local_photo_path TEXT,                 -- file on this phone
          start_date     TEXT NOT NULL,          -- yyyy-MM-dd
          end_date       TEXT,                   -- yyyy-MM-dd or NULL
          is_active      INTEGER NOT NULL DEFAULT 1,
          updated_at     TEXT NOT NULL,
          sync_state     TEXT NOT NULL DEFAULT 'synced'
        )''')
      ..execute('''
        CREATE TABLE schedules (
          id             TEXT PRIMARY KEY,
          medication_id  TEXT NOT NULL,
          time_of_day    TEXT NOT NULL,          -- HH:mm, local time
          days_mask      INTEGER NOT NULL,       -- Mon=1 … Sun=64
          quantity       REAL NOT NULL DEFAULT 1,
          updated_at     TEXT NOT NULL,
          sync_state     TEXT NOT NULL DEFAULT 'synced'
        )''')
      ..execute('CREATE INDEX idx_schedules_med ON schedules(medication_id)')
      ..execute('''
        CREATE TABLE dose_logs (
          id             TEXT PRIMARY KEY,       -- UUID made on the phone
          schedule_id    TEXT NOT NULL,
          medication_id  TEXT NOT NULL,
          scheduled_at   INTEGER NOT NULL,       -- epoch ms
          status         TEXT NOT NULL,          -- taken | skipped | missed
          taken_at       INTEGER,
          updated_at     INTEGER NOT NULL,
          deleted        INTEGER NOT NULL DEFAULT 0,
          sync_state     TEXT NOT NULL DEFAULT 'pending', -- pending | synced
          UNIQUE (schedule_id, scheduled_at)
        )''')
      ..execute('CREATE INDEX idx_dose_logs_time ON dose_logs(scheduled_at)')
      ..execute('CREATE INDEX idx_dose_logs_sync ON dose_logs(sync_state)')
      ..execute('''
        CREATE TABLE meta (
          key   TEXT PRIMARY KEY,
          value TEXT
        )''');
    await batch.commit(noResult: true);
  }
}
