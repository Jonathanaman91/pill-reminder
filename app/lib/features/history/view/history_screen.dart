import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/message_view.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../dashboard/domain/today_dose.dart';
import '../bloc/history_cubit.dart';

/// The History tab: how well the last 30 days went, day by day, so the user
/// (or their doctor) can see which doses were taken, skipped or missed.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => HistoryCubit(context.read<DashboardRepository>()),
      child: const _HistoryView(),
    );
  }
}

class _HistoryView extends StatelessWidget {
  const _HistoryView();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<HistoryCubit, HistoryState>(
          builder: (context, state) {
            if (state.status == HistoryStatus.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.status == HistoryStatus.failure) {
              return MessageView(
                icon: Icons.error_outline_rounded,
                title: 'Couldn’t open your history',
                body: 'It is still saved on this phone. Please try again.',
                actionLabel: 'Try again',
                actionIcon: Icons.refresh_rounded,
                onAction: context.read<HistoryCubit>().load,
              );
            }

            final today = DateTime.now();
            final week = state.summaryFor(7, today);
            final month = state.summaryFor(30, today);

            return ListView(
              padding: EdgeInsets.fromLTRB(AppSpace.screen, AppSpace.lg, AppSpace.screen,
                  AppSpace.section + MediaQuery.paddingOf(context).bottom),
              children: [
                Text('Last 30 days', style: text.labelMedium),
                const SizedBox(height: AppSpace.xs),
                Text('History', style: text.headlineMedium),
                const SizedBox(height: AppSpace.lg),
                if (state.days.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xxl),
                    child: Text(
                      'Your past doses will show here from tomorrow.',
                      style: text.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(child: _SummaryCard(label: 'Last 7 days', summary: week)),
                      const SizedBox(width: AppSpace.md),
                      Expanded(child: _SummaryCard(label: 'Last 30 days', summary: month)),
                    ],
                  ),
                  for (final day in state.days) _DaySection(day: day),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.summary});

  final String label;
  final AdherenceSummary summary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final percent = summary.percent;

    return Container(
      padding: const EdgeInsets.all(AppRadius.cardPadding),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelMedium),
          const SizedBox(height: AppSpace.xs),
          Text(percent == null ? '—' : '$percent%', style: text.headlineMedium?.tabular),
          Text('taken', style: text.bodyMedium),
          const SizedBox(height: AppSpace.sm),
          Text(
            '${summary.skipped} skipped · ${summary.missed} missed',
            style: text.labelMedium?.tabular,
          ),
        ],
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.day});

  final DoseDay day;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final summary = AdherenceSummary.of(day.doses);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final isYesterday = day.day.year == yesterday.year &&
        day.day.month == yesterday.month &&
        day.day.day == yesterday.day;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isYesterday ? 'Yesterday' : DateFormat('EEEE, d MMM').format(day.day),
                  style: text.titleSmall,
                ),
              ),
              Text('${summary.taken} of ${summary.total} taken', style: text.labelMedium?.tabular),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          for (final dose in day.doses) _HistoryRow(dose: dose),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.dose});

  final TodayDose dose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (IconData icon, Color color, String detail) = switch (dose.status) {
      DoseStatus.taken => (
          Icons.check_circle_rounded,
          AppColors.ink,
          dose.takenAt == null ? 'Taken' : 'Taken at ${DateFormat.Hm().format(dose.takenAt!)}',
        ),
      DoseStatus.skipped => (
          Icons.remove_circle_outline_rounded,
          AppColors.inkSecondary,
          dose.skipReason == null ? 'Skipped' : 'Skipped · ${dose.skipReason}',
        ),
      _ => (Icons.cancel_outlined, AppColors.danger, 'Missed'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(DateFormat.Hm().format(dose.scheduledAt), style: text.titleMedium?.tabular),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dose.name, style: text.titleMedium),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: text.bodyMedium?.tabular.copyWith(
                    color: dose.status == DoseStatus.missed ? AppColors.danger : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Icon(icon, color: color, semanticLabel: detail),
        ],
      ),
    );
  }
}
