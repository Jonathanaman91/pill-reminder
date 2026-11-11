import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

/// Centred message for the empty and error states, with one clear action.
class DashboardMessage extends StatelessWidget {
  const DashboardMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
  });

  const DashboardMessage.empty({super.key, required VoidCallback onAddMedication})
      : icon = Icons.medication_rounded,
        title = 'Add your first medication',
        body = 'Set the times you take it, and today’s doses will show up here '
            'even when you have no signal.',
        actionLabel = 'Add medication',
        actionIcon = Icons.add_rounded,
        onAction = onAddMedication;

  const DashboardMessage.error({super.key, required VoidCallback onRetry})
      : icon = Icons.cloud_off_rounded,
        title = 'Couldn’t load your schedule',
        body = 'Connect to the internet once to download it. '
            'After that, it works offline.',
        actionLabel = 'Try again',
        actionIcon = Icons.refresh_rounded,
        onAction = onRetry;

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.screen),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: AppColors.inkSecondary),
              const SizedBox(height: AppSpace.lg),
              Text(title, style: text.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: AppSpace.sm),
              Text(body, style: text.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: AppSpace.xl),
              FilledButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
