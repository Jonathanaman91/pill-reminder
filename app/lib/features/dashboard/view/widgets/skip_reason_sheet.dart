import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/today_dose.dart';

/// The reasons offered when skipping. Kept short, because they show up in
/// the History tab and, counted across all users, in the admin analytics.
const skipReasons = [
  'Side effects or felt unwell',
  'Ran out of medicine',
  'Doctor told me to skip it',
  'Too late, will take the next dose',
  'Other reason',
];

/// Skipping a medicine can be risky, so it takes more than one tap: the user
/// reads a short warning and picks why. Returns the reason, or null when
/// they back out (which skips nothing).
Future<String?> showSkipReasonSheet(BuildContext context, TodayDose dose) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (_) => _SkipReasonSheet(dose: dose),
  );
}

class _SkipReasonSheet extends StatefulWidget {
  const _SkipReasonSheet({required this.dose});

  final TodayDose dose;

  @override
  State<_SkipReasonSheet> createState() => _SkipReasonSheetState();
}

class _SkipReasonSheetState extends State<_SkipReasonSheet> {
  String? _reason;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dose = widget.dose;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.screen, 0, AppSpace.screen, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Skip this dose?', style: text.titleLarge),
            const SizedBox(height: AppSpace.xs),
            Text(
              '${dose.name} · ${DateFormat.Hm().format(dose.scheduledAt)} · ${dose.detailLabel}',
              style: text.bodyMedium?.tabular,
            ),
            const SizedBox(height: AppSpace.lg),
            // A plain, calm warning: no alarming colours, just the facts.
            Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.inkSecondary),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      'Missing a dose can make some medicines work less well. If you are not '
                      'sure, ask your doctor or pharmacist before skipping.',
                      style: text.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Text('Why are you skipping it?', style: text.titleSmall),
            const SizedBox(height: AppSpace.xs),
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (value) => setState(() => _reason = value),
              child: Column(
                children: [
                  for (final reason in skipReasons)
                    RadioListTile<String>(
                      value: reason,
                      title: Text(reason),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Don’t skip'),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  // Neutral, not the accent: skipping is never the action we promote.
                  child: FilledButton.tonal(
                    onPressed: _reason == null ? null : () => Navigator.pop(context, _reason),
                    child: const Text('Skip dose'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
