// Runs the real SQLite code (through sqflite's desktop engine), so editing
// and deleting are checked against an actual database, not a fake.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pill_reminder/core/database/app_database.dart';
import 'package:pill_reminder/features/dashboard/data/dashboard_local_source.dart';
import 'package:pill_reminder/features/dashboard/domain/today_dose.dart';
import 'package:pill_reminder/features/medications/data/medication_local_source.dart';
import 'package:pill_reminder/features/medications/domain/medication.dart';
import 'package:pill_reminder/features/profile/data/profile_repository.dart';
import 'package:pill_reminder/features/profile/domain/health_profile.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

NewMedication _metformin({
  String name = 'Metformin',
  List<ClockTime> times = const [ClockTime(8, 0), ClockTime(20, 0)],
  int daysMask = WeekDays.everyDay,
  double quantity = 1,
}) =>
    NewMedication(
      name: name,
      form: DosageForm.tablet,
      dosageAmount: 500,
      dosageUnit: 'mg',
      quantity: quantity,
      times: times,
      daysMask: daysMask,
      startDate: DateTime(2026, 11, 1),
      instructions: 'After food',
    );

void main() {
  late AppDatabase database;
  late MedicationLocalSource local;
  late DashboardLocalSource dashboard;
  final noon = DateTime(2026, 11, 12, 12); // a Thursday

  Future<String> dbPath() async => p.join(await getDatabasesPath(), 'pill_reminder.db');

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Test files run at the same time: each needs its own database folder.
    await databaseFactory.setDatabasesPath(Directory.systemTemp.createTempSync('pill_db_').path);
  });

  setUp(() async {
    await deleteDatabase(await dbPath());
    database = await AppDatabase.open();
    local = MedicationLocalSource(database);
    dashboard = DashboardLocalSource(database);
  });

  tearDown(() => database.db.close());

  Future<Map<String, String>> scheduleIdsByTime(String medicationId) async => {
        for (final s in await database.db.query('schedules',
            where: 'medication_id = ? AND deleted = 0', whereArgs: [medicationId]))
          s['time_of_day'] as String: s['id'] as String,
      };

  /// What the sync does after a successful upload.
  Future<List<Map<String, Object?>>> upload() async {
    final pending = await local.pendingForUpload();
    await local.markUploaded(pending);
    return pending;
  }

  test('a saved medication can be read back for the list and the edit form', () async {
    final id = await local.insert(_metformin(daysMask: 21, quantity: 2), noon);

    final saved = (await local.all()).single;
    expect(saved.id, id);
    expect(saved.name, 'Metformin');
    expect(saved.form, DosageForm.tablet);
    expect(saved.dosageAmount, 500);
    expect(saved.quantity, 2);
    expect(saved.times.map((t) => t.hhmm), ['08:00', '20:00']);
    expect(saved.daysMask, 21);
    expect(saved.startDate, DateTime(2026, 11, 1));
    expect(saved.endDate, isNull);
    expect(saved.instructions, 'After food');
  });

  test('editing changes the details, keeps unchanged times and swaps the rest', () async {
    final id = await local.insert(_metformin(), noon);
    await upload();
    final before = await scheduleIdsByTime(id);

    await local.update(
      id,
      _metformin(name: 'Metformin XR', times: const [ClockTime(8, 0), ClockTime(13, 0)], quantity: 2),
      noon.add(const Duration(minutes: 5)),
    );

    final edited = (await local.all()).single;
    expect(edited.name, 'Metformin XR');
    expect(edited.quantity, 2);
    expect(edited.times.map((t) => t.hhmm), ['08:00', '13:00']);

    final after = await scheduleIdsByTime(id);
    expect(after['08:00'], before['08:00'], reason: 'an unchanged time keeps its row');
    expect(after.containsKey('20:00'), isFalse);
    expect(after['13:00'], isNotNull);

    // The upload tells the server about all three rows, one of them deleted.
    final sent = (await local.pendingForUpload()).single;
    expect(sent['name'], 'Metformin XR');
    expect(sent['deleted'], isFalse);
    final schedules = (sent['schedules'] as List).cast<Map<String, Object?>>();
    expect({for (final s in schedules) s['timeOfDay']: s['deleted']},
        {'08:00': false, '13:00': false, '20:00': true});

    // After the upload the removed time is gone for good, and nothing is pending.
    await local.markUploaded([sent]);
    expect(await database.db.query('schedules', where: 'medication_id = ?', whereArgs: [id]),
        hasLength(2));
    expect(await local.pendingForUpload(), isEmpty);
  });

  test('a dose already taken today stays taken after an edit', () async {
    final id = await local.insert(_metformin(), noon);
    final morning = (await dashboard.loadSnapshot(noon))
        .doses
        .firstWhere((d) => d.scheduledAt.hour == 8);
    await dashboard.saveDoseStatus(morning, DoseStatus.taken, noon);

    await local.update(id, _metformin(name: 'Metformin XR'), noon);

    final doses = (await dashboard.loadSnapshot(noon)).doses;
    expect(doses.map((d) => d.name).toSet(), {'Metformin XR'});
    expect(doses.firstWhere((d) => d.scheduledAt.hour == 8).status, DoseStatus.taken);
  });

  test('putting a removed time back before the upload reuses its row', () async {
    final id = await local.insert(_metformin(), noon);
    await upload();
    final before = await scheduleIdsByTime(id);

    await local.update(id, _metformin(times: const [ClockTime(8, 0)]), noon);
    await local.update(id, _metformin(), noon);

    expect(await scheduleIdsByTime(id), before);
  });

  test('deleting hides the medication at once and removes it after the upload', () async {
    final keepId = await local.insert(_metformin(name: 'Amlodipine'), noon);
    final id = await local.insert(_metformin(), noon);
    await upload();

    await local.softDelete(id, noon.add(const Duration(minutes: 5)));

    // Gone from the list, the dashboard and the reminders straight away…
    expect((await local.all()).map((m) => m.id), [keepId]);
    expect((await dashboard.loadSnapshot(noon)).doses.map((d) => d.name).toSet(), {'Amlodipine'});
    expect((await dashboard.upcomingDoses(noon)).map((d) => d.medicationId).toSet(), {keepId});

    // …but still in the table, so the server can be told.
    final sent = (await local.pendingForUpload()).single;
    expect(sent['id'], id);
    expect(sent['deleted'], isTrue);
    expect((sent['schedules'] as List).every((s) => (s as Map)['deleted'] == true), isTrue);

    await local.markUploaded([sent]);
    expect(await database.db.query('medications', where: 'id = ?', whereArgs: [id]), isEmpty);
    expect(await database.db.query('schedules', where: 'medication_id = ?', whereArgs: [id]),
        isEmpty);
    expect((await local.all()).map((m) => m.id), [keepId]);
  });

  test('a delete is not lost if the upload fails', () async {
    final id = await local.insert(_metformin(), noon);
    await upload();
    await local.softDelete(id, noon);

    // No markUploaded: the phone was offline. The delete must still be queued.
    expect((await local.pendingForUpload()).single['deleted'], isTrue);
    expect(await local.all(), isEmpty);
  });

  test('editing a medication that was deleted meanwhile fails cleanly', () async {
    final id = await local.insert(_metformin(), noon);
    await local.softDelete(id, noon);
    expect(() => local.update(id, _metformin(name: 'Ghost'), noon), throwsStateError);
  });

  test('an older database (version 2) is upgraded without losing data', () async {
    await database.db.close();
    final path = await dbPath();
    await deleteDatabase(path);

    // The tables exactly as version 2 of the app created them.
    final old = await openDatabase(path, version: 2, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE medications (
          id TEXT PRIMARY KEY, name TEXT NOT NULL, dosage_amount REAL NOT NULL,
          dosage_unit TEXT NOT NULL, form TEXT NOT NULL, instructions TEXT,
          photo_path TEXT, local_photo_path TEXT, start_date TEXT NOT NULL, end_date TEXT,
          is_active INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL,
          sync_state TEXT NOT NULL DEFAULT 'synced')''');
      await db.execute('''
        CREATE TABLE schedules (
          id TEXT PRIMARY KEY, medication_id TEXT NOT NULL, time_of_day TEXT NOT NULL,
          days_mask INTEGER NOT NULL, quantity REAL NOT NULL DEFAULT 1,
          updated_at TEXT NOT NULL, sync_state TEXT NOT NULL DEFAULT 'synced')''');
      await db.execute('''
        CREATE TABLE dose_logs (
          id TEXT PRIMARY KEY, schedule_id TEXT NOT NULL, medication_id TEXT NOT NULL,
          scheduled_at INTEGER NOT NULL, status TEXT NOT NULL, taken_at INTEGER,
          updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
          sync_state TEXT NOT NULL DEFAULT 'pending', UNIQUE (schedule_id, scheduled_at))''');
      await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)');
    });
    await old.insert('medications', {
      'id': 'old-1', 'name': 'Aspirin', 'dosage_amount': 100, 'dosage_unit': 'mg',
      'form': 'tablet', 'start_date': '2026-11-01', 'updated_at': '2026-11-01T00:00:00.000Z',
    });
    await old.insert('schedules', {
      'id': 'old-s1', 'medication_id': 'old-1', 'time_of_day': '07:30', 'days_mask': 127,
      'updated_at': '2026-11-01T00:00:00.000Z',
    });
    await old.close();

    database = await AppDatabase.open(); // runs the upgrade
    local = MedicationLocalSource(database);
    dashboard = DashboardLocalSource(database);

    expect((await local.all()).single.name, 'Aspirin');
    expect((await dashboard.loadSnapshot(noon)).doses.single.name, 'Aspirin');
    await local.softDelete('old-1', noon);
    expect(await local.all(), isEmpty);
  });

  test('an "Other" form keeps the text the user typed', () async {
    final id = await local.insert(
      NewMedication(
        name: 'Nicotine',
        form: DosageForm.other,
        formDetail: ' Patch ',
        dosageAmount: 21,
        dosageUnit: 'mg',
        quantity: 1,
        times: const [ClockTime(8, 0)],
        daysMask: WeekDays.everyDay,
        startDate: DateTime(2026, 11, 1),
      ),
      noon,
    );
    final saved = (await local.all()).single;
    expect(saved.formDetail, 'Patch');
    expect(saved.detailLabel, 'Patch · 21 mg');
    expect((await local.pendingForUpload()).single['formDetail'], 'Patch');
    expect((await dashboard.loadSnapshot(noon)).doses.single.detailLabel, 'Patch · 21 mg');

    // Switching to a normal form drops the typed text.
    await local.update(id, _metformin(name: 'Nicotine'), noon);
    expect((await local.all()).single.formDetail, isNull);
  });

  test('a skipped dose keeps its reason, and it is uploaded', () async {
    await local.insert(_metformin(), noon);
    final morning = (await dashboard.loadSnapshot(noon)).doses.first;
    final saved = await dashboard.saveDoseStatus(morning, DoseStatus.skipped, noon,
        skipReason: 'Ran out of medicine');
    expect(saved.skipReason, 'Ran out of medicine');
    expect((await dashboard.loadSnapshot(noon)).doses.first.skipReason, 'Ran out of medicine');
    expect((await dashboard.pendingDoseLogs()).single['skip_reason'], 'Ran out of medicine');

    // Changing it to taken clears the reason.
    await dashboard.saveDoseStatus(morning, DoseStatus.taken, noon, skipReason: 'ignored');
    expect((await dashboard.loadSnapshot(noon)).doses.first.skipReason, isNull);
  });

  test('history lists past days; unmarked doses count as missed', () async {
    await local.insert(_metformin(), noon); // started 1 Nov, 08:00 and 20:00
    final yesterday8 = DateTime(2026, 11, 11, 8);
    final dose = (await dashboard.upcomingDoses(DateTime(2026, 11, 11, 7)))
        .firstWhere((d) => d.scheduledAt == yesterday8);
    await dashboard.saveDoseStatus(dose, DoseStatus.taken, yesterday8);

    final days = await dashboard.history(noon, days: 3);
    expect(days.map((d) => d.day), [DateTime(2026, 11, 11), DateTime(2026, 11, 10), DateTime(2026, 11, 9)]);
    expect(days.first.doses.map((d) => d.status), [DoseStatus.taken, DoseStatus.missed]);
    expect(days.last.doses.every((d) => d.status == DoseStatus.missed), isTrue);
  });

  test('the health profile is stored on the phone and marked for upload', () async {
    final store = ProfileLocalStore(database);
    expect(await store.read(), HealthProfile.empty);
    final profile = HealthProfile(
      dateOfBirth: DateTime(1958, 4, 12),
      gender: Gender.female,
      conditions: const ['Diabetes'],
      allergies: 'Penicillin',
    );
    await store.write(profile, pending: true);
    expect(await store.read(), profile);
    expect(await store.isPending(), isTrue);
    expect(profile.ageOn(noon), 68);
    expect(profile.summary(noon), 'Age 68 · Diabetes');

    // Logging out wipes it with everything else.
    await database.clearAll();
    expect(await store.read(), HealthProfile.empty);
  });
}
