import 'package:equatable/equatable.dart';

/// Matches the `dosage_form` enum in backend/db/schema.sql.
enum DosageForm {
  tablet('Tablet', ['mg', 'mcg', 'g', 'IU'], countable: true),
  capsule('Capsule', ['mg', 'mcg', 'g', 'IU'], countable: true),
  liquid('Liquid', ['ml', 'mg']),
  injection('Injection', ['ml', 'units', 'mg', 'IU']),
  inhaler('Inhaler', ['puffs', 'mcg']),
  drops('Drops', ['drops', 'ml']),
  cream('Cream', ['g', '%']),
  other('Other', ['mg', 'ml', 'g', 'units', 'IU']);

  const DosageForm(this.label, this.units, {this.countable = false});

  final String label;

  /// Units that make sense for this form; the first is the default.
  final List<String> units;

  /// Tablets and capsules are counted ("2 tablets"); others are measured.
  final bool countable;
}

/// A time of day in 24-hour format, e.g. 08:00. (Kept free of Flutter's
/// TimeOfDay so this file has no UI dependency and is easy to unit test.)
class ClockTime extends Equatable implements Comparable<ClockTime> {
  const ClockTime(this.hour, this.minute)
      : assert(hour >= 0 && hour < 24),
        assert(minute >= 0 && minute < 60);

  final int hour;
  final int minute;

  /// "08:00" — the format the API and SQLite use.
  String get hhmm => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(ClockTime other) => (hour * 60 + minute) - (other.hour * 60 + other.minute);

  @override
  List<Object?> get props => [hour, minute];
}

/// Days of the week as bits: Mon = 1, Tue = 2 … Sun = 64 (127 = every day).
abstract final class WeekDays {
  static const everyDay = 127;
  static const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static int bit(int index) => 1 << index; // index 0 = Monday
  static bool has(int mask, int index) => mask & bit(index) != 0;
  static int toggle(int mask, int index) => mask ^ bit(index);
}

/// Everything the Add Medication form collects.
class NewMedication extends Equatable {
  const NewMedication({
    required this.name,
    required this.form,
    required this.dosageAmount,
    required this.dosageUnit,
    required this.quantity,
    required this.times,
    required this.daysMask,
    required this.startDate,
    this.endDate,
    this.instructions,
    this.photoPath,
  });

  final String name;
  final DosageForm form;
  final double dosageAmount;
  final String dosageUnit;

  /// Tablets/capsules per dose (always 1 for measured forms).
  final double quantity;
  final List<ClockTime> times;
  final int daysMask;
  final DateTime startDate;
  final DateTime? endDate;
  final String? instructions;

  /// Temporary file from the camera/gallery; the repository copies it into
  /// the app's own folder.
  final String? photoPath;

  @override
  List<Object?> get props => [name, form, dosageAmount, dosageUnit, quantity, times,
        daysMask, startDate, endDate, instructions, photoPath];
}
