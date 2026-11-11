import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/dashboard_snapshot.dart';

/// Date, headline, progress bar and streak — the "how am I doing today" block.
class DaySummary extends StatelessWidget {
  const DaySummary({
    super.key,
    required this.snapshot,
    required this.onOpenAccount,
    this.onAddMedication,
  });

  final DashboardSnapshot snapshot;
  final VoidCallback onOpenAccount;

  /// Hidden when null (e.g. the empty state already shows the main button).
  final VoidCallback? onAddMedication;

  String get _headline {
    final s = snapshot;
    if (s.total == 0) return 'Nothing scheduled today';
    if (s.dayComplete) return 'All doses taken';
    if (s.remaining == 0) return 'No doses left today';
    return s.remaining == 1 ? '1 dose left today' : '${s.remaining} doses left today';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                DateFormat('EEEE, d MMMM').format(snapshot.now),
                style: text.labelMedium?.tabular,
              ),
            ),
            IconButton(
              onPressed: onOpenAccount,
              tooltip: 'Account',
              icon: const Icon(Icons.account_circle_rounded, color: AppColors.inkSecondary),
            ),
            if (onAddMedication != null)
              // Neutral tonal button: the accent colour is saved for the
              // "Mark as taken" action below.
              IconButton.filledTonal(
                onPressed: onAddMedication,
                tooltip: 'Add medication',
                icon: const Icon(Icons.add_rounded),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Text(_headline, style: text.headlineMedium?.tabular),
        if (snapshot.total > 0) ...[
          const SizedBox(height: AppSpace.lg),
          _ProgressRow(snapshot: snapshot),
          const SizedBox(height: AppSpace.md),
          _StreakRow(snapshot: snapshot),
        ],
      ],
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: snapshot.progress),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 6,
              borderRadius: const BorderRadius.all(Radius.circular(AppRadius.full)),
              semanticsLabel: 'Doses taken today',
              semanticsValue: '${snapshot.takenCount} of ${snapshot.total}',
            ),
          ),
        ),
        const SizedBox(width: AppSpace.md),
        Text(
          '${snapshot.takenCount} of ${snapshot.total} taken',
          style: text.labelMedium?.tabular,
        ),
      ],
    );
  }
}

class _StreakRow extends StatelessWidget {
  const _StreakRow({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final streak = snapshot.currentStreak;

    return Row(
      children: [
        Icon(
          Icons.local_fire_department_rounded,
          size: 18,
          color: streak > 0 ? AppColors.accent : AppColors.inkTertiary,
        ),
        const SizedBox(width: AppSpace.xs + 2), // optical gap: the flame has side bearing
        Flexible(
          child: Text(
            streak > 0 ? '$streak-day streak' : 'Take every dose today to start a streak',
            style: text.titleSmall?.tabular,
          ),
        ),
        if (snapshot.best > 0 && streak > 0) ...[
          const SizedBox(width: AppSpace.sm),
          Text('Best ${snapshot.best}', style: text.labelMedium?.tabular),
        ],
      ],
    );
  }
}
