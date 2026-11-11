import 'package:intl/intl.dart';

import '../../features/dashboard/domain/today_dose.dart';

/// One notification to schedule.
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.scheduleId,
    required this.scheduledAt,
  });

  final int id;
  final DateTime at;
  final String title;
  final String body;

  /// The dose slot this reminder belongs to (sent back when tapped).
  final String scheduleId;
  final DateTime scheduledAt;

  @override
  String toString() => '$id@${at.millisecondsSinceEpoch}';
}

/// Pure logic (no plugins) so it can be unit-tested: turns upcoming doses
/// into notifications.
///
///   • one reminder at the dose time
///   • one follow-up [followUpAfter] later, in case the first was missed
///   • nothing for doses already taken or skipped
///   • nothing in the past, at most [maxReminders] in total (Android caps
///     each app at about 500 scheduled alarms)
abstract final class ReminderPlanner {
  static const followUpAfter = Duration(minutes: 30);
  static const maxReminders = 200;
  static final _hm = DateFormat.Hm();

  static List<PlannedReminder> plan(List<TodayDose> doses, DateTime now) {
    final result = <PlannedReminder>[];
    for (final d in doses) {
      if (d.status.isResolved) continue;
      final due = d.scheduledAt;
      final follow = due.add(followUpAfter);

      if (due.isAfter(now)) {
        result.add(PlannedReminder(
          id: idFor(d.scheduleId, due, followUp: false),
          at: due,
          title: 'Time for ${d.name}',
          body: d.detailLabel,
          scheduleId: d.scheduleId,
          scheduledAt: due,
        ));
      }
      if (follow.isAfter(now)) {
        result.add(PlannedReminder(
          id: idFor(d.scheduleId, due, followUp: true),
          at: follow,
          title: 'Did you take ${d.name}?',
          body: 'It was due at ${_hm.format(due)}. Tap to mark it as taken.',
          scheduleId: d.scheduleId,
          scheduledAt: due,
        ));
      }
    }
    result.sort((a, b) => a.at.compareTo(b.at));
    return result.length > maxReminders ? result.sublist(0, maxReminders) : result;
  }

  /// Stable notification id for a dose slot, so the same dose always gets the
  /// same id and can be cancelled when it's taken. FNV-1a hash, kept to 31
  /// bits because Android ids are signed 32-bit integers.
  static int idFor(String scheduleId, DateTime scheduledAt, {required bool followUp}) {
    final key = '$scheduleId|${scheduledAt.millisecondsSinceEpoch}|${followUp ? 'f' : 'd'}';
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }
}
