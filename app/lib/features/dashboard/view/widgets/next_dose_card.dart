import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/medication_photo.dart';
import '../../domain/today_dose.dart';

/// The featured dose. Holds the screen's ONE accent-coloured button.
class NextDoseCard extends StatelessWidget {
  const NextDoseCard({
    super.key,
    required this.dose,
    required this.now,
    required this.busy,
    required this.onTake,
    required this.onSkip,
  });

  final TodayDose dose;
  final DateTime now;
  final bool busy;
  final VoidCallback onTake;
  final VoidCallback onSkip;

  String get _relative {
    final diff = dose.scheduledAt.difference(now);
    final mins = diff.inMinutes.abs();
    final span = mins < 60 ? '$mins min' : '${mins ~/ 60} h ${mins % 60} min';
    return switch (dose.status) {
      DoseStatus.upcoming => 'in $span',
      DoseStatus.due => diff.isNegative && mins >= 5 ? '$span late' : 'Due now',
      DoseStatus.missed => 'Missed · $span ago',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isMissed = dose.status == DoseStatus.missed;

    return Container(
      padding: const EdgeInsets.all(AppRadius.cardPadding),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          DateFormat.Hm().format(dose.scheduledAt),
                          style: text.displaySmall?.tabular,
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Text(
                          _relative,
                          style: text.labelMedium?.tabular.copyWith(
                            color: isMissed ? AppColors.danger : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    Text(dose.name, style: text.titleLarge),
                    const SizedBox(height: AppSpace.xs),
                    Text(dose.detailLabel, style: text.bodyMedium?.tabular),
                  ],
                ),
              ),
              if (dose.photo != null) ...[
                const SizedBox(width: AppSpace.md),
                // Photo sits inside the card's padding → radius = card − padding (8).
                MedicationPhoto(source: dose.photo!, radius: AppRadius.cardInner, size: 64),
              ],
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          Row(
            children: [
              Expanded(
                // Radius comes from the theme: AppRadius.control = card − padding.
                child: FilledButton.icon(
                  onPressed: busy ? null : onTake,
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: busy
                        ? const SizedBox.square(
                            key: ValueKey('busy'),
                            dimension: 18,
                            // The button is disabled while saving, so use
                            // ink (not white) to stay visible on its grey fill.
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.inkSecondary),
                          )
                        : const Icon(Icons.check_rounded, key: ValueKey('idle')),
                  ),
                  label: Text(isMissed ? 'Mark as taken late' : 'Mark as taken'),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              TextButton(
                onPressed: busy ? null : onSkip,
                child: const Text('Skip'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
