import 'package:equatable/equatable.dart';

enum DoseStatus {
  /// More than [DosePolicy.dueEarly] before the scheduled time.
  upcoming,

  /// Inside the window where the user should take it now.
  due,
  taken,
  skipped,

  /// The window passed without a log. The user can still mark it taken late.
  missed;

  bool get isResolved => this == taken || this == skipped;
  bool get canMarkTaken => !isResolved;
}

/// Timing rules in one place, so the dashboard, the notifications step and
/// the server can all agree on what "due" and "missed" mean.
abstract final class DosePolicy {
  static const dueEarly = Duration(minutes: 15);
  static const missedAfter = Duration(minutes: 60);

  static DoseStatus resolve({
    required DateTime scheduledAt,
    required DateTime now,
    String? loggedStatus,
  }) {
    switch (loggedStatus) {
      case 'taken':
        return DoseStatus.taken;
      case 'skipped':
        return DoseStatus.skipped;
      case 'missed':
        return DoseStatus.missed;
    }
    if (now.isBefore(scheduledAt.subtract(dueEarly))) return DoseStatus.upcoming;
    if (now.isAfter(scheduledAt.add(missedAfter))) return DoseStatus.missed;
    return DoseStatus.due;
  }
}

enum DayPart {
  morning('Morning'),
  afternoon('Afternoon'),
  evening('Evening'),
  night('Night');

  const DayPart(this.label);
  final String label;

  static DayPart of(DateTime t) => switch (t.hour) {
        >= 5 && < 12 => morning,
        >= 12 && < 17 => afternoon,
        >= 17 && < 21 => evening,
        _ => night,
      };
}

/// One scheduled slot for today, e.g. "Metformin 500 mg at 08:00".
class TodayDose extends Equatable {
  const TodayDose({
    required this.scheduleId,
    required this.medicationId,
    required this.name,
    required this.dosageAmount,
    required this.dosageUnit,
    required this.form,
    required this.quantity,
    required this.scheduledAt,
    required this.status,
    this.instructions,
    this.photo,
    this.logId,
    this.takenAt,
  });

  final String scheduleId;
  final String medicationId;
  final String name;
  final double dosageAmount;
  final String dosageUnit;
  final String form; // tablet, capsule, liquid, …
  final double quantity; // e.g. 2 tablets
  final String? instructions;

  /// Pill-bottle photo: a file path on this phone, or an http(s) URL.
  final String? photo;
  final DateTime scheduledAt;
  final DoseStatus status;
  final String? logId;
  final DateTime? takenAt;

  /// Unique for this slot today; used to track which row is busy.
  String get key => '$scheduleId@${scheduledAt.millisecondsSinceEpoch}';

  DayPart get dayPart => DayPart.of(scheduledAt);

  /// "500 mg · 2 tablets · After food"
  String get detailLabel {
    final parts = <String>['${_trim(dosageAmount)} $dosageUnit'];
    if (form == 'tablet' || form == 'capsule') {
      parts.add('${_trim(quantity)} ${quantity == 1 ? form : '${form}s'}');
    }
    if (instructions != null && instructions!.trim().isNotEmpty) {
      parts.add(instructions!.trim());
    }
    return parts.join(' · ');
  }

  TodayDose copyWith({DoseStatus? status, String? logId, DateTime? takenAt}) => TodayDose(
        scheduleId: scheduleId,
        medicationId: medicationId,
        name: name,
        dosageAmount: dosageAmount,
        dosageUnit: dosageUnit,
        form: form,
        quantity: quantity,
        instructions: instructions,
        photo: photo,
        scheduledAt: scheduledAt,
        status: status ?? this.status,
        logId: logId ?? this.logId,
        takenAt: takenAt ?? this.takenAt,
      );

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  List<Object?> get props => [scheduleId, scheduledAt, name, dosageAmount, dosageUnit,
        form, quantity, instructions, photo, status, logId, takenAt];
}
