import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pill_reminder/core/theme/app_theme.dart';
import 'package:pill_reminder/features/medications/domain/medication.dart';
import 'package:pill_reminder/features/medications/view/widgets/time_wheel_sheet.dart';

void main() {
  group('"Rings in" headline', () {
    final now = DateTime(2026, 11, 19, 17, 36); // a Thursday
    final start = DateTime(2026, 11, 1);

    String label(ClockTime t, {int days = WeekDays.everyDay, DateTime? from}) =>
        ringsInLabel(untilNextRing(t, days, from ?? start, now));

    test('later today', () {
      expect(label(const ClockTime(18, 56)), 'Rings in 1 h 20 min');
      expect(label(const ClockTime(17, 50)), 'Rings in 14 min');
      expect(label(const ClockTime(19, 36)), 'Rings in 2 h');
    });

    test('already passed today rolls to tomorrow', () {
      expect(label(const ClockTime(17, 36)), 'Rings in 1 day');
      expect(label(const ClockTime(8, 0)), 'Rings in 14 h 24 min');
    });

    test('follows the chosen days and the start date', () {
      // Mondays only (bit 0): next Monday is 23 Nov.
      expect(label(const ClockTime(18, 0), days: 1), 'Rings in 4 days');
      expect(label(const ClockTime(17, 36), from: DateTime(2026, 11, 22)), 'Rings in 3 days');
    });

    test('no days chosen', () {
      expect(label(const ClockTime(8, 0), days: 0), 'Reminder time');
    });
  });

  testWidgets('scrolling the wheels picks the time', (tester) async {
    ClockTime? result;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showTimeWheelSheet(
            context,
            initial: const ClockTime(8, 0),
            daysMask: WeekDays.everyDay,
            startDate: DateTime(2026),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Hours wheel down two rows (08 → 10), minutes up one row (00 → 59).
    final wheels = find.byType(ListWheelScrollView);
    await tester.drag(wheels.at(0), const Offset(0, -112));
    await tester.pumpAndSettle();
    await tester.drag(wheels.at(1), const Offset(0, 56));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(result, const ClockTime(10, 59));
  });

  testWidgets('cancel returns nothing', (tester) async {
    ClockTime? result = const ClockTime(1, 1);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showTimeWheelSheet(
            context,
            initial: const ClockTime(8, 0),
            daysMask: WeekDays.everyDay,
            startDate: DateTime(2026),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
