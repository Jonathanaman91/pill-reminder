// Taps through the "second step" dialogs: marking a dose, deleting a
// medication and saving an edit must all need a confirmation.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pill_reminder/core/notifications/notification_service.dart';
import 'package:pill_reminder/core/notifications/reminder_planner.dart';
import 'package:pill_reminder/core/theme/app_theme.dart';
import 'package:pill_reminder/features/dashboard/data/dashboard_repository.dart';
import 'package:pill_reminder/features/dashboard/data/demo_dashboard_repository.dart';
import 'package:pill_reminder/features/dashboard/view/dashboard_screen.dart';
import 'package:pill_reminder/features/dashboard/view/widgets/next_dose_card.dart';
import 'package:pill_reminder/features/medications/data/demo_medication_repository.dart';
import 'package:pill_reminder/features/medications/data/medication_repository.dart';
import 'package:pill_reminder/features/medications/view/medications_screen.dart';
import 'package:pill_reminder/features/reminders/bloc/reminders_cubit.dart';

class _NoReminders implements ReminderPlatform {
  @override
  Stream<DoseNotificationTap> get taps => const Stream.empty();
  @override
  DoseNotificationTap? takeLaunchTap() => null;
  @override
  Future<ReminderPermission> permission() async => ReminderPermission.granted;
  @override
  Future<bool> requestNotifications() async => true;
  @override
  Future<void> requestExactAlarms() async {}
  @override
  Future<void> requestBackgroundRun() async {}
  @override
  Future<void> openAppDetails() async {}
  @override
  Future<String?> deviceMaker() async => null;
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> replaceAll(List<PlannedReminder> reminders, {required bool exact}) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> scheduleTest({required bool exact, Duration delay = const Duration(seconds: 10)}) async {}
}

const _settle = Duration(seconds: 2); // demo repositories answer within 1 s
final _dialog = find.byType(AlertDialog);

Finder _inDialog(Finder what) => find.descendant(of: _dialog, matching: what);

/// The first pump starts any animation or timer; the second lets it finish.
Future<void> _wait(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(_settle);
}

void main() {
  late DemoDashboardRepository dashboard;

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    dashboard = DemoDashboardRepository();
    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<DashboardRepository>.value(value: dashboard),
        RepositoryProvider<MedicationRepository>.value(
            value: DemoMedicationRepository(dashboard)),
      ],
      child: BlocProvider(
        create: (_) => RemindersCubit(platform: _NoReminders(), repository: dashboard),
        child: MaterialApp(theme: buildAppTheme(), home: home),
      ),
    ));
    await _wait(tester);
    await _wait(tester);
  }

  /// Lets snack bars close and stops the repository's once-a-minute timer.
  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpWidget(const SizedBox());
    await dashboard.dispose();
  }

  testWidgets('marking a dose as taken needs a confirmation', (tester) async {
    await pumpApp(tester, DashboardScreen(onAddMedication: () {}, onOpenAccount: () {}));
    final markButton =
        find.descendant(of: find.byType(NextDoseCard), matching: find.byType(FilledButton));
    expect(find.text('0 of 5 taken'), findsOneWidget);

    // First tap only asks.
    await tester.tap(markButton);
    await _wait(tester);
    expect(_inDialog(find.text('Mark as taken?')), findsOneWidget);
    expect(find.text('0 of 5 taken'), findsOneWidget);

    // Backing out records nothing.
    await tester.tap(_inDialog(find.text('Not yet')));
    await _wait(tester);
    expect(_dialog, findsNothing);
    expect(find.text('0 of 5 taken'), findsOneWidget);

    // Confirming records exactly one dose.
    await tester.tap(markButton);
    await _wait(tester);
    await tester.tap(_inDialog(find.byType(FilledButton)));
    await _wait(tester);
    expect(_dialog, findsNothing);
    expect(find.text('1 of 5 taken'), findsOneWidget);

    await finish(tester);
  });

  testWidgets('skipping a dose needs a warning and a reason', (tester) async {
    await pumpApp(tester, DashboardScreen(onAddMedication: () {}, onOpenAccount: () {}));
    final sheet = find.byType(BottomSheet);
    Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
    final skipButton = inSheet(find.widgetWithText(FilledButton, 'Skip dose'));

    await tester.tap(find.widgetWithText(TextButton, 'Skip'));
    await _wait(tester);
    expect(inSheet(find.text('Skip this dose?')), findsOneWidget);
    expect(inSheet(find.textContaining('ask your doctor or pharmacist')), findsOneWidget);
    // No reason chosen yet: the button does nothing.
    expect(tester.widget<FilledButton>(skipButton).onPressed, isNull);
    await tester.tap(inSheet(find.text('Don’t skip')));
    await _wait(tester);
    expect(find.textContaining('skipped'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Skip'));
    await _wait(tester);
    await tester.tap(inSheet(find.text('Ran out of medicine')));
    await _wait(tester);
    await tester.tap(skipButton);
    await _wait(tester);
    expect(find.textContaining('skipped'), findsWidgets);
    // The reason is kept with the dose.
    final skipped = (await dashboard.upcomingDoses(days: 1)).where((d) => d.skipReason != null);
    expect(skipped.single.skipReason, 'Ran out of medicine');

    await finish(tester);
  });

  testWidgets('deleting a medication needs a confirmation', (tester) async {
    await pumpApp(tester, MedicationsScreen(onAddMedication: () {}));
    expect(find.text('4 medications'), findsOneWidget);

    Future<void> openDeleteDialog() async {
      await tester.tap(find.byTooltip('Edit or delete Atorvastatin'));
      await _wait(tester);
      await tester.tap(find.text('Delete'));
      await _wait(tester);
    }

    await openDeleteDialog();
    expect(_inDialog(find.text('Delete Atorvastatin?')), findsOneWidget);
    await tester.tap(_inDialog(find.text('Keep it')));
    await _wait(tester);
    expect(find.text('Atorvastatin'), findsOneWidget);
    expect(dashboard.medications, hasLength(4));

    await openDeleteDialog();
    await tester.tap(_inDialog(find.text('Delete')));
    await _wait(tester);
    expect(find.text('Atorvastatin'), findsNothing);
    expect(find.text('3 medications'), findsOneWidget);
    expect(find.text('Atorvastatin deleted'), findsOneWidget);
    // Its doses leave the schedule as well.
    expect((await dashboard.upcomingDoses(days: 1)).map((d) => d.name),
        isNot(contains('Atorvastatin')));

    await finish(tester);
  });

  testWidgets('saving an edit needs a confirmation', (tester) async {
    await pumpApp(tester, MedicationsScreen(onAddMedication: () {}));

    await tester.tap(find.byTooltip('Edit or delete Amlodipine'));
    await _wait(tester);
    await tester.tap(find.text('Edit'));
    await _wait(tester);
    expect(find.text('Edit medication'), findsOneWidget);
    // The form opens filled in.
    expect(find.widgetWithText(TextFormField, 'Amlodipine'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '5'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Amlodipine'), 'Amlodipine XR');
    // The saved reminder time is further down the form.
    await tester.scrollUntilVisible(find.text('09:30'), 200,
        scrollable: find.byType(Scrollable).first);
    final saveButton = find.widgetWithText(FilledButton, 'Save changes');

    // First tap asks; "Keep editing" changes nothing.
    await tester.tap(saveButton);
    await _wait(tester);
    expect(_inDialog(find.text('Save changes?')), findsOneWidget);
    await tester.tap(_inDialog(find.text('Keep editing')));
    await _wait(tester);
    expect(find.text('Edit medication'), findsOneWidget);
    expect(dashboard.medications.map((m) => m.name), contains('Amlodipine'));

    // Confirming saves and returns to the list.
    await tester.tap(saveButton);
    await _wait(tester);
    await tester.tap(_inDialog(find.byType(FilledButton)));
    await _wait(tester);
    await _wait(tester);
    expect(find.text('Edit medication'), findsNothing);
    expect(find.text('Amlodipine XR'), findsOneWidget);
    expect(dashboard.medications.map((m) => m.name), contains('Amlodipine XR'));
    expect(dashboard.medications, hasLength(4)); // edited, not added

    await finish(tester);
  });

  testWidgets('saving an edit with no changes just closes the form', (tester) async {
    await pumpApp(tester, MedicationsScreen(onAddMedication: () {}));

    await tester.tap(find.byTooltip('Edit or delete Metformin'));
    await _wait(tester);
    await tester.tap(find.text('Edit'));
    await _wait(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await _wait(tester);

    expect(_dialog, findsNothing);
    expect(find.text('Edit medication'), findsNothing);
    expect(find.text('Nothing was changed.'), findsOneWidget);

    await finish(tester);
  });
}
