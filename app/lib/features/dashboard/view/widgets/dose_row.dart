import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/today_dose.dart';

/// One line in the day's schedule. No card, no border — rows are separated by
/// whitespace, and the time column lines up thanks to tabular figures.
class DoseRow extends StatelessWidget {
  const DoseRow({
    super.key,
    required this.dose,
    required this.busy,
    required this.onTake,
    required this.onUndo,
  });

  final TodayDose dose;
  final bool busy;
  final VoidCallback onTake;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final resolved = dose.status.isResolved;
    final missed = dose.status == DoseStatus.missed;

    final timeColor = missed
        ? AppColors.danger
        : resolved
            ? AppColors.inkTertiary
            : AppColors.ink;

    final detail = switch (dose.status) {
      DoseStatus.taken when dose.takenAt != null =>
        'Taken at ${DateFormat.Hm().format(dose.takenAt!)} · ${dose.detailLabel}',
      DoseStatus.skipped => 'Skipped · ${dose.detailLabel}',
      DoseStatus.missed => 'Missed · ${dose.detailLabel}',
      _ => dose.detailLabel,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              DateFormat.Hm().format(dose.scheduledAt),
              style: text.titleMedium?.tabular.copyWith(color: timeColor),
            ),
          ),
          Expanded(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: resolved ? 0.6 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dose.name, style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: text.bodyMedium?.tabular,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: _control(),
          ),
        ],
      ),
    );
  }

  Widget _control() {
    if (busy) {
      return const SizedBox.square(
        key: ValueKey('busy'),
        dimension: 48,
        child: Center(
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (dose.status.isResolved) {
      return IconButton(
        key: const ValueKey('resolved'),
        onPressed: onUndo,
        tooltip: 'Undo',
        icon: Icon(
          dose.status == DoseStatus.taken
              ? Icons.check_circle_rounded
              : Icons.remove_circle_outline_rounded,
          color: AppColors.ink,
        ),
      );
    }
    return IconButton(
      key: const ValueKey('open'),
      onPressed: onTake,
      tooltip: 'Mark ${dose.name} as taken',
      icon: const Icon(Icons.radio_button_unchecked_rounded, color: AppColors.inkSecondary),
    );
  }
}
