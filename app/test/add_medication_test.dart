import 'package:flutter_test/flutter_test.dart';
import 'package:pill_reminder/core/validation/validators.dart';
import 'package:pill_reminder/features/medications/bloc/add_medication_cubit.dart';
import 'package:pill_reminder/features/medications/data/medication_repository.dart';
import 'package:pill_reminder/features/medications/domain/medication.dart';

class _FakeRepo implements MedicationRepository {
  NewMedication? saved;
  bool fail = false;

  @override
  Future<void> add(NewMedication medication) async {
    if (fail) throw Exception('disk full');
    saved = medication;
  }
}

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
}
