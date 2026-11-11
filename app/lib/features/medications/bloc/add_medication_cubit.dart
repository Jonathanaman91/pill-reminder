import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/medication_repository.dart';
import '../domain/medication.dart';

final class AddMedicationState extends Equatable {
  AddMedicationState({
    this.photoPath,
    this.form = DosageForm.tablet,
    String? unit,
    this.quantity = 1,
    this.times = const [],
    this.everyDay = true,
    this.customDays = _weekdays,
    DateTime? startDate,
    this.endDate,
    this.showErrors = false,
    this.submitting = false,
    this.saveError,
  })  : unit = unit ?? form.units.first,
        startDate = startDate ?? _today();

  static const _weekdays = 31; // Mon–Fri
  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  final String? photoPath;
  final DosageForm form;
  final String unit;
  final double quantity;
  final List<ClockTime> times; // always sorted
  final bool everyDay;
  final int customDays;
  final DateTime startDate;
  final DateTime? endDate;

  /// Becomes true after the first Save tap, so errors don't shout at the
  /// user before they've had a chance to fill anything in.
  final bool showErrors;
  final bool submitting;
  final String? saveError;

  int get daysMask => everyDay ? WeekDays.everyDay : customDays;

  // Checks for the parts that are not text boxes (text boxes use Validators).
  String? get timesError => times.isEmpty ? 'Add at least one time.' : null;
  String? get daysError => daysMask == 0 ? 'Pick at least one day.' : null;
  String? get endDateError =>
      endDate != null && endDate!.isBefore(startDate) ? 'Must be on or after the start date.' : null;
  bool get choicesValid => timesError == null && daysError == null && endDateError == null;

  AddMedicationState copyWith({
    String? Function()? photoPath,
    DosageForm? form,
    String? unit,
    double? quantity,
    List<ClockTime>? times,
    bool? everyDay,
    int? customDays,
    DateTime? startDate,
    DateTime? Function()? endDate,
    bool? showErrors,
    bool? submitting,
    String? Function()? saveError,
  }) =>
      AddMedicationState(
        photoPath: photoPath != null ? photoPath() : this.photoPath,
        form: form ?? this.form,
        unit: unit ?? this.unit,
        quantity: quantity ?? this.quantity,
        times: times ?? this.times,
        everyDay: everyDay ?? this.everyDay,
        customDays: customDays ?? this.customDays,
        startDate: startDate ?? this.startDate,
        endDate: endDate != null ? endDate() : this.endDate,
        showErrors: showErrors ?? this.showErrors,
        submitting: submitting ?? this.submitting,
        saveError: saveError != null ? saveError() : this.saveError,
      );

  @override
  List<Object?> get props => [photoPath, form, unit, quantity, times, everyDay, customDays,
        startDate, endDate, showErrors, submitting, saveError];
}

/// ViewModel for the Add Medication screen. Text boxes live in the widget
/// (TextEditingControllers); everything else lives here.
class AddMedicationCubit extends Cubit<AddMedicationState> {
  AddMedicationCubit(this._repository) : super(AddMedicationState());

  final MedicationRepository _repository;

  static const maxTimes = 12;
  static const minQuantity = 0.5;
  static const maxQuantity = 10.0;

  void setPhoto(String? path) => emit(state.copyWith(photoPath: () => path));

  void setForm(DosageForm form) => emit(state.copyWith(
        form: form,
        unit: form.units.contains(state.unit) ? state.unit : form.units.first,
        quantity: form.countable ? state.quantity : 1,
      ));

  void setUnit(String unit) => emit(state.copyWith(unit: unit));

  void changeQuantity(double delta) {
    final next = (state.quantity + delta).clamp(minQuantity, maxQuantity);
    emit(state.copyWith(quantity: next.toDouble()));
  }

  /// Returns a message to show if the time can't be added, otherwise null.
  String? addTime(ClockTime time) {
    if (state.times.contains(time)) return '${time.hhmm} is already in the list.';
    if (state.times.length >= maxTimes) return 'You can add up to $maxTimes times a day.';
    emit(state.copyWith(times: [...state.times, time]..sort()));
    return null;
  }

  void removeTime(ClockTime time) =>
      emit(state.copyWith(times: state.times.where((t) => t != time).toList()));

  void setEveryDay(bool value) => emit(state.copyWith(everyDay: value));

  void toggleDay(int index) =>
      emit(state.copyWith(customDays: WeekDays.toggle(state.customDays, index)));

  void setStartDate(DateTime date) => emit(state.copyWith(startDate: date));

  void setEndDate(DateTime? date) => emit(state.copyWith(endDate: () => date));

  void revealErrors() => emit(state.copyWith(showErrors: true));

  /// Text values must already be validated by the form. Returns true if saved.
  Future<bool> save({
    required String name,
    required double strength,
    String? instructions,
  }) async {
    if (state.submitting || !state.choicesValid) return false;
    emit(state.copyWith(submitting: true, saveError: () => null));
    try {
      await _repository.add(NewMedication(
        name: name.trim(),
        form: state.form,
        dosageAmount: strength,
        dosageUnit: state.unit,
        quantity: state.quantity,
        times: state.times,
        daysMask: state.daysMask,
        startDate: state.startDate,
        endDate: state.endDate,
        instructions: (instructions?.trim().isEmpty ?? true) ? null : instructions!.trim(),
        photoPath: state.photoPath,
      ));
      emit(state.copyWith(submitting: false));
      return true;
    } catch (_) {
      emit(state.copyWith(
        submitting: false,
        saveError: () => 'Couldn’t save on this phone. Please try again.',
      ));
      return false;
    }
  }
}
