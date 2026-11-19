// Guest mode: use the app without an account. Nothing may be sent to the
// server, the session must survive a restart, and creating an account later
// must keep what the guest saved.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pill_reminder/core/database/app_database.dart';
import 'package:pill_reminder/core/network/api_client.dart';
import 'package:pill_reminder/core/sync/sync_pusher.dart';
import 'package:pill_reminder/core/theme/app_theme.dart';
import 'package:pill_reminder/features/auth/bloc/auth_bloc.dart';
import 'package:pill_reminder/features/auth/data/auth_repository.dart';
import 'package:pill_reminder/features/auth/data/demo_auth_repository.dart';
import 'package:pill_reminder/features/auth/domain/auth_user.dart';
import 'package:pill_reminder/features/auth/view/login_screen.dart';
import 'package:pill_reminder/features/dashboard/bloc/dashboard_bloc.dart';
import 'package:pill_reminder/features/dashboard/data/dashboard_local_source.dart';
import 'package:pill_reminder/features/dashboard/data/dashboard_remote_source.dart';
import 'package:pill_reminder/features/dashboard/data/dashboard_repository.dart';
import 'package:pill_reminder/features/medications/data/medication_local_source.dart';
import 'package:pill_reminder/features/medications/domain/medication.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fails the test if anything tries to reach the server.
class _NoNetwork extends Interceptor {
  int calls = 0;
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    calls++;
    handler.reject(DioException(requestOptions: options, message: 'network used in guest mode'));
  }
}

class _CountingPusher implements SyncPusher {
  int calls = 0;
  @override
  Future<void> pushPending() async => calls++;
}

void main() {
  group('ApiAuthRepository', () {
    late TokenStorage tokens;
    late ApiAuthRepository repo;
    late _NoNetwork network;
    var cleared = 0;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      tokens = TokenStorage();
      network = _NoNetwork();
      cleared = 0;
      repo = ApiAuthRepository(
        dio: Dio()..interceptors.add(network),
        tokens: tokens,
        clearLocalData: () async => cleared++,
      );
    });

    test('starting guest mode needs no network and survives a restart', () async {
      expect(await repo.continueAsGuest(), AuthUser.guest);
      expect(await repo.restoreSession(), AuthUser.guest);
      expect(await tokens.readRefreshToken(), isNull);
      expect(network.calls, 0);
    });

    test('leaving guest mode wipes the phone without calling the server', () async {
      await repo.continueAsGuest();
      await repo.logOut();
      expect(cleared, 1);
      expect(await repo.restoreSession(), isNull);
      expect(network.calls, 0);
    });

    test('an account with no refresh token is not restored', () async {
      await tokens.saveUserJson('{"id":"u1","email":"a@b.com","fullName":"A B","role":"user"}');
      expect(await repo.restoreSession(), isNull);
    });
  });

  group('AuthBloc', () {
    test('guest request signs in as the guest', () async {
      final bloc = AuthBloc(repository: DemoAuthRepository())..add(const AuthGuestRequested());
      final state = await bloc.stream.firstWhere((s) => s.status == AuthStatus.authenticated);
      expect(state.user!.isGuest, isTrue);
      await bloc.close();
    });
  });

  group('Offline-first repository in guest mode', () {
    late AppDatabase database;
    late _NoNetwork network;
    late _CountingPusher pusher;
    late bool hasAccount;
    late OfflineFirstDashboardRepository repo;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      // Test files run at the same time: each needs its own database folder.
      await databaseFactory.setDatabasesPath(Directory.systemTemp.createTempSync('pill_db_').path);
    });

    setUp(() async {
      await deleteDatabase(p.join(await getDatabasesPath(), 'pill_reminder.db'));
      database = await AppDatabase.open();
      network = _NoNetwork();
      pusher = _CountingPusher();
      hasAccount = false;
      repo = OfflineFirstDashboardRepository(
        local: DashboardLocalSource(database),
        remote: DashboardRemoteSource(Dio()..interceptors.add(network)),
        pushers: [pusher],
        hasAccount: () async => hasAccount,
      );
    });

    tearDown(() async {
      await repo.dispose();
      await database.db.close();
    });

    test('sync stays on the phone and keeps changes waiting', () async {
      final now = DateTime.now();
      await MedicationLocalSource(database).insert(
        NewMedication(
          name: 'Metformin',
          form: DosageForm.tablet,
          dosageAmount: 500,
          dosageUnit: 'mg',
          quantity: 1,
          times: const [ClockTime(8, 0)],
          daysMask: WeekDays.everyDay,
          startDate: DateTime(now.year, now.month, now.day),
        ),
        now,
      );

      expect(await repo.sync(), SyncOutcome.localOnly);
      expect(network.calls, 0);
      expect(pusher.calls, 0);
      // Still queued, so a later account gets it.
      expect(await MedicationLocalSource(database).pendingForUpload(), hasLength(1));

      // Once there is an account, the same outbox is uploaded.
      hasAccount = true;
      await repo.sync();
      expect(pusher.calls, 1);
    });

    test('the dashboard opens (empty) instead of waiting for a server', () async {
      final bloc = DashboardBloc(repository: repo)..add(const DashboardStarted());
      final state = await bloc.stream
          .firstWhere((s) => s.status == DashboardStatus.ready && s.sync == SyncIndicator.localOnly)
          .timeout(const Duration(seconds: 5));
      expect(state.snapshot!.total, 0);
      await bloc.close();
    });
  });

  testWidgets('"Continue without an account" asks first, then starts guest mode', (tester) async {
    final repo = DemoAuthRepository();
    final bloc = AuthBloc(repository: repo);
    await tester.pumpWidget(RepositoryProvider<AuthRepository>.value(
      value: repo,
      child: BlocProvider.value(
        value: bloc,
        child: MaterialApp(theme: buildAppTheme(), home: const LoginScreen()),
      ),
    ));

    final guestButton = find.text('Continue without an account');
    await tester.ensureVisible(guestButton);
    await tester.tap(guestButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Use without an account?'), findsOneWidget);

    await tester.tap(find.text('Go back'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(bloc.state.status, AuthStatus.unknown);

    await tester.ensureVisible(guestButton);
    await tester.tap(guestButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Continue as guest'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(bloc.state.user?.isGuest, isTrue);
  });

  testWidgets('a guest opening the login form gets a back button and no guest option',
      (tester) async {
    final repo = DemoAuthRepository();
    await tester.pumpWidget(RepositoryProvider<AuthRepository>.value(
      value: repo,
      child: BlocProvider(
        create: (_) => AuthBloc(repository: repo),
        child: MaterialApp(theme: buildAppTheme(), home: const LoginScreen(fromGuest: true)),
      ),
    ));
    expect(find.text('Continue without an account'), findsNothing);
    expect(find.textContaining('will be added to your account'), findsOneWidget);
  });
}
