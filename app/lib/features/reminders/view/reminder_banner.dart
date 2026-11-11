import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../bloc/reminders_cubit.dart';

/// Shown on the dashboard only when reminders can't work properly. Uses a
/// neutral button, so the accent stays on "Mark as taken".
class ReminderBanner extends StatelessWidget {
  const ReminderBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RemindersCubit>().state;
    final text = Theme.of(context).textTheme;

    final content = switch (state.needsAttention ? state.permission : null) {
      ReminderPermission.notificationsOff => (
          icon: Icons.notifications_off_rounded,
          title: 'Reminders are off',
          body: 'Allow notifications so your phone alerts you when a dose is due.',
          action: state.notificationsRefused ? 'Open settings' : 'Turn on',
        ),
      ReminderPermission.exactAlarmsOff => (
          icon: Icons.alarm_off_rounded,
          title: 'Reminders may arrive late',
          body: 'Allow “Alarms & reminders” so alerts arrive on the minute.',
          action: 'Allow',
        ),
      _ => null,
    };

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: content == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: AppSpace.lg),
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                    AppRadius.cardPadding, AppSpace.md, AppSpace.sm, AppSpace.md),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
                ),
                child: Row(
                  children: [
                    Icon(content.icon, color: AppColors.danger, size: 22),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(content.title, style: text.titleSmall),
                          const SizedBox(height: 2),
                          Text(content.body, style: text.bodyMedium),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    TextButton(
                      onPressed: () => context.read<RemindersCubit>().requestPermission(),
                      child: Text(content.action),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
