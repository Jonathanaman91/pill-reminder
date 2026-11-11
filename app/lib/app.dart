import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/notifications/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/view/auth_gate.dart';
import 'features/dashboard/data/dashboard_repository.dart';
import 'features/facilities/data/facility_repository.dart';
import 'features/facilities/data/location_service.dart';
import 'features/medications/data/medication_repository.dart';
import 'features/medications/view/add_medication_screen.dart';
import 'features/reminders/bloc/reminders_cubit.dart';

class PillReminderApp extends StatelessWidget {
  const PillReminderApp({
    super.key,
    required this.authRepository,
    required this.dashboardRepository,
    required this.medicationRepository,
    required this.reminderPlatform,
    required this.facilityRepository,
    required this.locationService,
  });

  final AuthRepository authRepository;
  final DashboardRepository dashboardRepository;
  final MedicationRepository medicationRepository;
  final ReminderPlatform reminderPlatform;
  final FacilityRepository facilityRepository;
  final LocationService locationService;

  @override
  Widget build(BuildContext context) {
    // Everything placed above MaterialApp is available on every screen/route.
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(value: authRepository),
        RepositoryProvider<DashboardRepository>.value(value: dashboardRepository),
        RepositoryProvider<MedicationRepository>.value(value: medicationRepository),
        RepositoryProvider<FacilityRepository>.value(value: facilityRepository),
        RepositoryProvider<LocationService>.value(value: locationService),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => AuthBloc(repository: authRepository)..add(const AuthStarted()),
          ),
          BlocProvider(
            create: (_) => RemindersCubit(
              platform: reminderPlatform,
              repository: dashboardRepository,
            ),
          ),
        ],
        child: MaterialApp(
          title: 'Pill Reminder',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: const AuthGate(),
          routes: {
            '/medications/new': (context) => const AddMedicationScreen(),
          },
        ),
      ),
    );
  }
}
