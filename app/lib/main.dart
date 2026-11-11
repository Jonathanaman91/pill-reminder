import 'package:flutter/material.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/network/api_client.dart';
import 'core/notifications/notification_service.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/demo_auth_repository.dart';
import 'features/dashboard/data/dashboard_local_source.dart';
import 'features/dashboard/data/dashboard_remote_source.dart';
import 'features/dashboard/data/dashboard_repository.dart';
import 'features/dashboard/data/demo_dashboard_repository.dart';
import 'features/facilities/data/demo_facility_repository.dart';
import 'features/facilities/data/facility_repository.dart';
import 'features/facilities/data/location_service.dart';
import 'features/medications/data/demo_medication_repository.dart';
import 'features/medications/data/medication_local_source.dart';
import 'features/medications/data/medication_remote_source.dart';
import 'features/medications/data/medication_repository.dart';

/// flutter run                                   → demo data, no backend needed
/// flutter run --dart-define=DEMO_DATA=false     → real SQLite + API
/// flutter run --dart-define=DEMO_OFFLINE=true   → demo data, offline status line
///
/// 10.0.2.2 is how the Android emulator reaches "localhost" on your computer.
const _useDemoData = bool.fromEnvironment('DEMO_DATA', defaultValue: false);
const _demoOffline = bool.fromEnvironment('DEMO_OFFLINE');
const _apiBaseUrl =
    String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:3000/api/v1');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Dose alarms (Feature f). Safe to await: it never throws.
  final notifications = NotificationService();
  await notifications.init();

  final AuthRepository authRepository;
  final DashboardRepository dashboardRepository;
  final MedicationRepository medicationRepository;
  final FacilityRepository facilityRepository;

  if (_useDemoData) {
    authRepository = DemoAuthRepository();
    final demoDashboard = DemoDashboardRepository(simulateOffline: _demoOffline);
    dashboardRepository = demoDashboard;
    medicationRepository = DemoMedicationRepository(demoDashboard);
    facilityRepository = DemoFacilityRepository();
  } else {
    final database = await AppDatabase.open();
    final tokens = TokenStorage();
    final api = ApiClient(baseUrl: _apiBaseUrl, tokens: tokens);
    authRepository = ApiAuthRepository(
      dio: api.dio,
      tokens: tokens,
      clearLocalData: database.clearAll,
    );
    final medicationLocal = MedicationLocalSource(database);
    dashboardRepository = OfflineFirstDashboardRepository(
      local: DashboardLocalSource(database),
      remote: DashboardRemoteSource(api.dio),
      // Upload new medications (and their photos) before dose logs.
      pushers: [
        MedicationSyncPusher(local: medicationLocal, remote: MedicationRemoteSource(api.dio)),
      ],
    );
    medicationRepository = OfflineFirstMedicationRepository(
      local: medicationLocal,
      dashboard: dashboardRepository,
    );
    facilityRepository = CachedFacilityRepository(dio: api.dio, database: database);
  }

  runApp(PillReminderApp(
    authRepository: authRepository,
    dashboardRepository: dashboardRepository,
    medicationRepository: medicationRepository,
    reminderPlatform: notifications,
    facilityRepository: facilityRepository,
    // GPS is real even in demo mode; only the places are samples.
    locationService: GeolocatorLocationService(),
  ));
}
