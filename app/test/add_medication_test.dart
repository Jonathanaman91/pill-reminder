import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pill_reminder/core/validation/validators.dart';
import 'package:pill_reminder/features/medications/bloc/add_medication_cubit.dart';
import 'package:pill_reminder/features/medications/bloc/medications_cubit.dart';
import 'package:pill_reminder/features/medications/data/medication_repository.dart';
import 'package:pill_reminder/features/medications/domain/medication.dart';

class _FakeRepo implements MedicationRepository {
  NewMedication? saved;
  String? updatedId;
  final deletedIds = <String>[];
  List<Medication> stored = [];
  bool fail = false;
  final _changes = StreamController<void>.broadcast();

  @override
  Future<void> add(NewMedication medication) async {
    if (fail) throw Exception('disk full');
    saved = medication;
  }

  @override
  Future<List<Medication>> all() async {
    if (fail) throw Exception('disk error');
    return stored;
  }

  @override
  Future<void> update(String id, NewMedication changes) async {
    if (fail) throw Exception('disk full');
    updatedId = id;
    saved = changes;
  }

  @override
  Future<void> delete(String id) async {
    if (fail) throw Exception('disk full');
    deletedIds.add(id);
    stored = stored.where((m) => m.id != id).toList();
  }

  @override
  Stream<void> get changes => _changes.stream;

  void notifyChanged() => _changes.add(null);
}

final _metformin = Medication(
  id: 'med-1',
  name: 'Metformin',
  form: DosageForm.tablet,
  dosageAmount: 500,
  dosageUnit: 'mg',
  quantity: 2,
  times: const [ClockTime(8, 0), ClockTime(20, 0)],
  daysMask: 21, // Mon, Wed, Fri
  startDate: DateTime(2026, 11, 1),
  instructions: 'After food',
  photo: '/photos/metformin.jpg',
);

void main() {
  group('Validators', () {
    test('medication name', () {
      expect(Validators.medicationName(''), isNotNull);
      expect(Validators.medicationName('A'), isNotNull);
      expect(Validators.medicationName('Metformin <script>'), isNotNull);
      expect(Validators.medicationName('Vitamin D3 (1000 IU)'), isNull);
    });

    test('strength', () {
      expect(Validators.strength(''), 'Enter the strength.');
      expect(Validators.strength('abc'), isNotNull);
      expect(Validators.strength('0'), 'Must be more than 0.');
      expect(Validators.strength('0.1234'), 'Use up to 3 decimal places.');
      expect(Validators.strength('2,5'), isNull);
      expect(Validators.parseAmount('2,5'), 2.5);
    });
  });

  group('AddMedicationCubit', () {
    late _FakeRepo repo;
    late AddMedicationCubit cubit;

    setUp(() {
      repo = _FakeRepo();
      cubit = AddMedicationCubit(repo);
    });
    tearDown(() => cubit.close());

    test('times stay sorted and duplicates are refused', () {
      expect(cubit.addTime(const ClockTime(20, 0)), isNull);
      expect(cubit.addTime(const ClockTime(8, 0)), isNull);
      expect(cubit.addTime(const ClockTime(8, 0)), contains('already'));
      expect(cubit.state.times.map((t) => t.hhmm), ['08:00', '20:00']);
    });

    test('changing form resets unit and quantity when they no longer fit', () {
      cubit.changeQuantity(1); // 2 tablets
      cubit.setUnit('IU'); // liquids are not measured in IU
      cubit.setForm(DosageForm.liquid);
      expect(cubit.state.unit, 'ml');
      expect(cubit.state.quantity, 1);
    });

    test('quantity stays between 0.5 and 10', () {
      cubit.changeQuantity(-5);
      expect(cubit.state.quantity, 0.5);
      cubit.changeQuantity(50);
      expect(cubit.state.quantity, 10);
    });

    test('needs a time and a day; end date cannot be before start', () {
      expect(cubit.state.timesError, isNotNull);
      cubit.setEveryDay(false);
      for (var i = 0; i < 5; i++) {
        cubit.toggleDay(i); // turn Mon–Fri off
      }
      expect(cubit.state.daysError, isNotNull);
      cubit.setEndDate(cubit.state.startDate.subtract(const Duration(days: 1)));
      expect(cubit.state.endDateError, isNotNull);
    });

    test('will not save while choices are invalid', () async {
      expect(await cubit.save(name: 'Metformin', strength: 500), isFalse);
      expect(repo.saved, isNull);
    });

    test('saves a complete medication', () async {
      cubit
        ..addTime(const ClockTime(8, 0))
        ..addTime(const ClockTime(20, 0));
      final ok = await cubit.save(name: '  Metformin ', strength: 500, instructions: ' ');
      expect(ok, isTrue);
      expect(repo.saved!.name, 'Metformin');
      expect(repo.saved!.daysMask, WeekDays.everyDay);
      expect(repo.saved!.instructions, isNull);
      expect(repo.saved!.times, hasLength(2));
    });

    test('shows an error if saving fails', () async {
      repo.fail = true;
      cubit.addTime(const ClockTime(8, 0));
      expect(await cubit.save(name: 'Metformin', strength: 500), isFalse);
      expect(cubit.state.saveError, isNotNull);
      expect(cubit.state.submitting, isFalse);
    });
  });

  group('AddMedicationCubit while editing', () {
    late _FakeRepo repo;
    late AddMedicationCubit cubit;

    setUp(() {
      repo = _FakeRepo();
      cubit = AddMedicationCubit(repo, editing: _metformin);
    });
    tearDown(() => cubit.close());

    test('opens filled in with the saved medication', () {
      final s = cubit.state;
      expect(cubit.isEditing, isTrue);
      expect(s.form, DosageForm.tablet);
      expect(s.unit, 'mg');
      expect(s.quantity, 2);
      expect(s.times.map((t) => t.hhmm), ['08:00', '20:00']);
      expect(s.everyDay, isFalse);
      expect(s.daysMask, 21);
      expect(s.startDate, DateTime(2026, 11, 1));
      expect(s.photoPath, '/photos/metformin.jpg');
      expect(cubit.choicesChanged, isFalse);
    });

    test('notices a change, and its undo', () {
      cubit.removeTime(const ClockTime(20, 0));
      expect(cubit.choicesChanged, isTrue);
      cubit.addTime(const ClockTime(20, 0));
      expect(cubit.choicesChanged, isFalse);
    });

    test('showing errors alone does not count as a change', () {
      cubit.revealErrors();
      expect(cubit.choicesChanged, isFalse);
    });

    test('saving updates the same medication instead of adding one', () async {
      cubit.removeTime(const ClockTime(20, 0));
      final ok = await cubit.save(name: 'Metformin XR', strength: 750, instructions: 'After food');
      expect(ok, isTrue);
      expect(repo.updatedId, 'med-1');
      expect(repo.saved!.name, 'Metformin XR');
      expect(repo.saved!.dosageAmount, 750);
      expect(repo.saved!.times.map((t) => t.hhmm), ['08:00']);
      expect(repo.saved!.daysMask, 21);
    });
  });

  group('Medication labels', () {
    test('detail and schedule lines', () {
      expect(_metformin.detailLabel, '500 mg · 2 tablets · After food');
      expect(_metformin.scheduleLabel, '08:00 · 20:00 · Mon, Wed, Fri');
    });

    test('every day, one tablet, no note', () {
      final daily = Medication.fromNew(
        'x',
        NewMedication(
          name: ' Amlodipine ',
          form: DosageForm.tablet,
          dosageAmount: 2.5,
          dosageUnit: 'mg',
          quantity: 1,
          times: const [ClockTime(21, 0), ClockTime(9, 30)],
          daysMask: WeekDays.everyDay,
          startDate: DateTime(2026, 11, 1),
        ),
      );
      expect(daily.name, 'Amlodipine');
      expect(daily.detailLabel, '2.5 mg · 1 tablet');
      expect(daily.scheduleLabel, '09:30 · 21:00 · Every day');
    });
  });

  group('MedicationsCubit', () {
    late _FakeRepo repo;
    late MedicationsCubit cubit;

    setUp(() => repo = _FakeRepo()..stored = [_metformin]);
    tearDown(() => cubit.close());

    test('loads the saved medications', () async {
      cubit = MedicationsCubit(repo);
      expect(cubit.state.status, MedicationsStatus.loading);
      await pumpEventQueue();
      expect(cubit.state.status, MedicationsStatus.ready);
      expect(cubit.state.medications, [_metformin]);
    });

    test('reloads when the repository reports a change', () async {
      cubit = MedicationsCubit(repo);
      await pumpEventQueue();
      repo
        ..stored = []
        ..notifyChanged();
      await pumpEventQueue();
      expect(cubit.state.medications, isEmpty);
    });

    test('delete removes the row and reports it', () async {
      cubit = MedicationsCubit(repo);
      await pumpEventQueue();
      await cubit.delete(_metformin);
      expect(repo.deletedIds, ['med-1']);
      expect(cubit.state.medications, isEmpty);
      expect(cubit.state.deletingIds, isEmpty);
      expect(cubit.state.feedback!.message, 'Metformin deleted');
    });

    test('a failed delete keeps the row and says so', () async {
      cubit = MedicationsCubit(repo);
      await pumpEventQueue();
      repo.fail = true;
      await cubit.delete(_metformin);
      expect(cubit.state.deletingIds, isEmpty);
      expect(cubit.state.medications, [_metformin]);
      expect(cubit.state.feedback!.message, contains('delete Metformin'));
    });

    test('shows a failure when the first load fails', () async {
      repo.fail = true;
      cubit = MedicationsCubit(repo);
      await pumpEventQueue();
      expect(cubit.state.status, MedicationsStatus.failure);
    });
  });
}
