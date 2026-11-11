import 'package:flutter_test/flutter_test.dart';
import 'package:pill_reminder/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:pill_reminder/features/dashboard/domain/today_dose.dart';

TodayDose _dose(int hour, DoseStatus status) => TodayDose(
      scheduleId: 's$hour',
      medicationId: 'm',
      name: 'Metformin',
      dosageAmount: 500,
      dosageUnit: 'mg',
      form: 'tablet',
      quantity: 1,
      scheduledAt: DateTime(2026, 11, 11, hour),
      status: status,
    );

void main() {
  final at8 = DateTime(2026, 11, 11, 8);

  group('DosePolicy', () {
    test('upcoming before the 15-minute window', () {
      expect(
        DosePolicy.resolve(scheduledAt: at8, now: DateTime(2026, 11, 11, 7, 40)),
        DoseStatus.upcoming,
      );
    });

    test('due from 15 minutes early to 60 minutes late', () {
      expect(DosePolicy.resolve(scheduledAt: at8, now: DateTime(2026, 11, 11, 7, 45)),
          DoseStatus.due);
      expect(DosePolicy.resolve(scheduledAt: at8, now: DateTime(2026, 11, 11, 9)),
          DoseStatus.due);
    });

    test('missed after 60 minutes with no log', () {
      expect(DosePolicy.resolve(scheduledAt: at8, now: DateTime(2026, 11, 11, 9, 1)),
          DoseStatus.missed);
    });

    test('a saved log always wins over the clock', () {
      expect(
        DosePolicy.resolve(
            scheduledAt: at8, now: DateTime(2026, 11, 11, 23), loggedStatus: 'taken'),
        DoseStatus.taken,
      );
    });
  });

  group('DashboardSnapshot', () {
    final now = DateTime(2026, 11, 11, 12);

    test('streak grows by one when every dose today is taken', () {
      final s = DashboardSnapshot(
        now: now,
        doses: [_dose(8, DoseStatus.taken), _dose(20, DoseStatus.taken)],
        streakBeforeToday: 4,
        bestStreak: 4,
        streakAsOf: DateTime(2026, 11, 11),
      );
      expect(s.currentStreak, 5);
      expect(s.best, 5);
    });

    test('streak does not grow from an out-of-date server value', () {
      final s = DashboardSnapshot(
        now: now,
        doses: [_dose(8, DoseStatus.taken)],
        streakBeforeToday: 4,
        bestStreak: 9,
        streakAsOf: DateTime(2026, 11, 9),
      );
      expect(s.currentStreak, 4);
    });

    test('next dose prefers due, then upcoming, then latest missed', () {
      final s = DashboardSnapshot(
        now: now,
        doses: [
          _dose(7, DoseStatus.missed),
          _dose(9, DoseStatus.missed),
          _dose(20, DoseStatus.upcoming),
        ],
        streakBeforeToday: 0,
        bestStreak: 0,
      );
      expect(s.nextDose?.scheduleId, 's20');
      expect(s.remaining, 3);
    });

    test('groups doses into parts of the day', () {
      final s = DashboardSnapshot(
        now: now,
        doses: [_dose(8, DoseStatus.taken), _dose(9, DoseStatus.due), _dose(19, DoseStatus.upcoming)],
        streakBeforeToday: 0,
        bestStreak: 0,
      );
      expect(s.sections.map((x) => x.part), [DayPart.morning, DayPart.evening]);
      expect(s.sections.first.doses, hasLength(2));
    });
  });
}
