import 'package:equatable/equatable.dart';

import 'today_dose.dart';

/// Everything the dashboard shows, built from the local cache.
class DashboardSnapshot extends Equatable {
  const DashboardSnapshot({
    required this.now,
    required this.doses,
    required this.streakBeforeToday,
    required this.bestStreak,
    this.streakAsOf,
    this.lastSyncedAt,
    this.pendingSyncCount = 0,
  });

  /// The minute this snapshot was built. Part of equality, so a new snapshot
  /// each minute refreshes relative labels such as "in 25 min".
  final DateTime now;
  final List<TodayDose> doses; // sorted by time

  /// Server-calculated streak of fully-taken days ending YESTERDAY, as of
  /// [streakAsOf]. Today is added on the phone, so the streak still grows
  /// offline when the user finishes today's doses.
  final int streakBeforeToday;
  final int bestStreak;
  final DateTime? streakAsOf;

  final DateTime? lastSyncedAt;
  final int pendingSyncCount;

  /// True once the phone has data of its own (so it can work offline).
  bool get hasCache => lastSyncedAt != null || doses.isNotEmpty;

  int get total => doses.length;
  int get takenCount => doses.where((d) => d.status == DoseStatus.taken).length;
  int get remaining => doses.where((d) => !d.status.isResolved).length;
  double get progress => total == 0 ? 0 : takenCount / total;
  bool get dayComplete => total > 0 && takenCount == total;

  bool get streakIsCurrent {
    final asOf = streakAsOf;
    return asOf != null &&
        asOf.year == now.year &&
        asOf.month == now.month &&
        asOf.day == now.day;
  }

  int get currentStreak => streakBeforeToday + (streakIsCurrent && dayComplete ? 1 : 0);
  int get best => currentStreak > bestStreak ? currentStreak : bestStreak;

  /// The dose to feature at the top: anything due now, otherwise the next
  /// upcoming one, otherwise the most recent missed one (can still be taken).
  TodayDose? get nextDose {
    for (final status in [DoseStatus.due, DoseStatus.upcoming]) {
      for (final d in doses) {
        if (d.status == status) return d;
      }
    }
    for (final d in doses.reversed) {
      if (d.status == DoseStatus.missed) return d;
    }
    return null;
  }

  /// Doses grouped into Morning / Afternoon / Evening / Night, in time order.
  List<({DayPart part, List<TodayDose> doses})> get sections {
    final result = <({DayPart part, List<TodayDose> doses})>[];
    for (final dose in doses) {
      if (result.isNotEmpty && result.last.part == dose.dayPart) {
        result.last.doses.add(dose);
      } else {
        result.add((part: dose.dayPart, doses: [dose]));
      }
    }
    return result;
  }

  @override
  List<Object?> get props =>
      [now, doses, streakBeforeToday, bestStreak, streakAsOf, lastSyncedAt, pendingSyncCount];
}
