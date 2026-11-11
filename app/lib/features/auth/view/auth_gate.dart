import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../home/home_shell.dart';
import '../../reminders/bloc/reminders_cubit.dart';
import '../bloc/auth_bloc.dart';
import 'account_sheet.dart';
import 'login_screen.dart';

/// The app's home: shows the login screen or the dashboard depending on
/// AuthBloc, closes any open screens when the user logs in or out, and turns
/// dose reminders on/off with the session.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Coming back from Android Settings may have changed permissions, and a
    // new day may have started: re-check and reschedule.
    _lifecycle = AppLifecycleListener(
      onResume: () => context.read<RemindersCubit>().refreshPermission(forceReschedule: true),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<AuthBloc, AuthState>(
          listenWhen: (prev, curr) =>
              prev.status != curr.status || (curr.notice != null && prev.notice != curr.notice),
          listener: (context, state) {
            if (state.status == AuthStatus.authenticated) {
              context.read<RemindersCubit>().start();
            } else if (state.status == AuthStatus.unauthenticated) {
              context.read<RemindersCubit>().stop();
            }
            Navigator.of(context).popUntil((route) => route.isFirst);
            final notice = state.notice;
            if (notice != null) _showMessage(notice.message);
          },
        ),
        BlocListener<RemindersCubit, RemindersState>(
          listenWhen: (prev, curr) => curr.notice != null && prev.notice != curr.notice,
          listener: (context, state) => _showMessage(state.notice!.message),
        ),
      ],
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, state) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: switch (state.status) {
            // Reading the saved session takes a few milliseconds; show the plain
            // background instead of flashing a spinner.
            AuthStatus.unknown => const Scaffold(key: ValueKey('unknown')),
            AuthStatus.unauthenticated => const LoginScreen(key: ValueKey('login')),
            AuthStatus.authenticated => HomeShell(
                // A new key per user gives each account fresh screens and BLoCs.
                key: ValueKey('home-${state.user!.id}'),
                onAddMedication: () => Navigator.of(context).pushNamed('/medications/new'),
                onOpenAccount: () => showAccountSheet(context, state.user!),
              ),
          },
        ),
      ),
    );
  }
}
