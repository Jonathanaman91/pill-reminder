import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/domain/health_profile.dart';
import '../../profile/view/profile_screen.dart';
import '../../reminders/bloc/reminders_cubit.dart';
import '../bloc/auth_bloc.dart';
import '../domain/auth_user.dart';
import 'login_screen.dart';
import 'register_screen.dart';

Future<void> showAccountSheet(BuildContext context, AuthUser user) {
  void openForm(BuildContext sheetContext, Widget screen) {
    Navigator.of(sheetContext).pop();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (sheetContext) => _AccountSheet(
      user: user,
      onCreateAccount: () => openForm(sheetContext, const RegisterScreen(fromGuest: true)),
      onLogIn: () => openForm(sheetContext, const LoginScreen(fromGuest: true)),
      onProfile: () => openForm(sheetContext, const ProfileScreen()),
      onLogOut: () async {
        final auth = context.read<AuthBloc>();
        if (user.isGuest) {
          // Second step: for a guest this is the only copy of their data.
          final confirmed = await showConfirmDialog(
            sheetContext,
            title: 'Delete your guest data?',
            message: 'Your medications, reminders and dose history are only on this '
                'phone. They will be deleted and cannot be brought back.',
            confirmLabel: 'Delete',
            cancelLabel: 'Keep it',
            style: ConfirmStyle.destructive,
          );
          if (!confirmed || !sheetContext.mounted) return;
        }
        Navigator.of(sheetContext).pop();
        auth.add(const AuthLogoutRequested());
      },
    ),
  );
}

class _AccountSheet extends StatelessWidget {
  const _AccountSheet({
    required this.user,
    required this.onCreateAccount,
    required this.onLogIn,
    required this.onLogOut,
    required this.onProfile,
  });

  final AuthUser user;
  final VoidCallback onCreateAccount;
  final VoidCallback onLogIn;
  final VoidCallback onLogOut;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final guest = user.isGuest;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.screen, 0, AppSpace.screen, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(guest ? 'Guest' : user.fullName, style: text.titleLarge),
            const SizedBox(height: AppSpace.xs),
            Text(
              guest ? 'No account · everything is saved on this phone only' : user.email,
              style: text.bodyMedium,
            ),
            const SizedBox(height: AppSpace.xl),
            _ProfileRow(onTap: onProfile),
            const SizedBox(height: AppSpace.lg),
            const _RemindersRow(),
            const SizedBox(height: AppSpace.xl),
            if (guest) ...[
              Text(
                'Create an account to back up your medications, so you can get '
                'them back on a new phone. Nothing you saved is lost.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: AppSpace.lg),
              FilledButton(onPressed: onCreateAccount, child: const Text('Create an account')),
              const SizedBox(height: AppSpace.sm),
              TextButton(onPressed: onLogIn, child: const Text('I already have an account')),
              const SizedBox(height: AppSpace.xl),
            ] else ...[
              Text(
                'Logging out removes your saved schedule from this phone. '
                'Changes that haven’t synced yet will be lost.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: AppSpace.lg),
            ],
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
              icon: Icon(guest ? Icons.delete_outline_rounded : Icons.logout_rounded),
              label: Text(guest ? 'Delete guest data' : 'Log out'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Health profile · Age 67 · Diabetes" — opens the profile form.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<HealthProfile>(
      future: context.read<ProfileRepository>().load(),
      builder: (context, snapshot) => InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.control)),
        child: Row(
          children: [
            const Icon(Icons.favorite_border_rounded, color: AppColors.inkSecondary),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Health profile', style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    snapshot.data?.summary(DateTime.now()) ?? ' ',
                    style: text.bodyMedium?.tabular,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkSecondary),
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
      ReminderPermission.backgroundRestricted =>
        'On, but battery saving may block them while the app is closed',
      ReminderPermission.notificationsOff => 'Off · turn them on from the dashboard',
      null => 'Checking…',
    };

    final reminders = context.read<RemindersCubit>();
    final row = Row(
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
    if (!state.needsAutoStart) return row;

    // realme, OPPO, Xiaomi...: even with battery saving off, these phones stop
    // an app's alarms unless "Auto launch" / "Autostart" is on for it.
    final brand = state.deviceMaker!;
    final name = brand.length <= 4 ? brand.toUpperCase() : brand[0].toUpperCase() + brand.substring(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        const SizedBox(height: AppSpace.md),
        Text(
          'On $name phones, also turn on Auto launch (or Autostart) and allow background '
          'activity for Pill Reminder, so reminders ring when the app is closed.',
          style: text.bodyMedium,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: reminders.openPhoneSettings,
            child: const Text('Open phone settings'),
          ),
        ),
      ],
    );
  }
}
