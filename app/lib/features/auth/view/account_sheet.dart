import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/notifications/notification_service.dart';
import '../../reminders/bloc/reminders_cubit.dart';
import '../bloc/auth_bloc.dart';
import '../domain/auth_user.dart';

Future<void> showAccountSheet(BuildContext context, AuthUser user) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (sheetContext) => _AccountSheet(
      user: user,
      onLogOut: () {
        Navigator.of(sheetContext).pop();
        context.read<AuthBloc>().add(const AuthLogoutRequested());
      },
    ),
  );
}

class _AccountSheet extends StatelessWidget {
  const _AccountSheet({required this.user, required this.onLogOut});

  final AuthUser user;
  final VoidCallback onLogOut;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.screen, 0, AppSpace.screen, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(user.fullName, style: text.titleLarge),
            const SizedBox(height: AppSpace.xs),
            Text(user.email, style: text.bodyMedium),
            const SizedBox(height: AppSpace.xl),
            const _RemindersRow(),
            const SizedBox(height: AppSpace.xl),
            Text(
              'Logging out removes your saved schedule from this phone. '
              'Changes that haven’t synced yet will be lost.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: AppSpace.lg),
            OutlinedButton.icon(
              onPressed: onLogOut,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.divider),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
                ),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Log out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemindersRow extends StatelessWidget {
  const _RemindersRow();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final state = context.watch<RemindersCubit>().state;
    final on = state.permission != ReminderPermission.notificationsOff;

    final status = switch (state.permission) {
      ReminderPermission.granted => 'On · ${state.scheduledCount} alerts in the next 7 days',
      ReminderPermission.exactAlarmsOff => 'On, but alerts may arrive a few minutes late',
      ReminderPermission.notificationsOff => 'Off · turn them on from the dashboard',
      null => 'Checking…',
    };

    return Row(
      children: [
        Icon(
          on ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
          color: on ? AppColors.inkSecondary : AppColors.danger,
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reminders', style: text.titleSmall),
              const SizedBox(height: 2),
              Text(status, style: text.bodyMedium?.tabular),
            ],
          ),
        ),
        TextButton(
          onPressed: on
              ? () {
                  final reminders = context.read<RemindersCubit>();
                  Navigator.of(context).pop(); // close the sheet so the message is visible
                  reminders.sendTestReminder();
                }
              : null,
          child: const Text('Test'),
        ),
      ],
    );
  }
}
