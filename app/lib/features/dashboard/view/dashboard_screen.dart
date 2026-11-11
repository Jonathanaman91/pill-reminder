import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/message_view.dart';
import '../../reminders/view/reminder_banner.dart';
import '../bloc/dashboard_bloc.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard_snapshot.dart';
import '../domain/today_dose.dart';
import 'widgets/dashboard_skeleton.dart';
import 'widgets/day_summary.dart';
import 'widgets/dose_row.dart';
import 'widgets/next_dose_card.dart';
import 'widgets/sync_status_line.dart';

/// Entry point: creates the BLoC for this screen.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.onAddMedication,
    required this.onOpenAccount,
  });

  final VoidCallback onAddMedication;
  final VoidCallback onOpenAccount;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DashboardBloc(repository: context.read<DashboardRepository>())
        ..add(const DashboardStarted()),
      child: DashboardView(onAddMedication: onAddMedication, onOpenAccount: onOpenAccount),
    );
  }
}

/// The View in MVVM terms: it only draws state and forwards taps as events.
class DashboardView extends StatelessWidget {
  const DashboardView({
    super.key,
    required this.onAddMedication,
    required this.onOpenAccount,
  });

  final VoidCallback onAddMedication;
  final VoidCallback onOpenAccount;

  void _showFeedback(BuildContext context, DashboardFeedback feedback) {
    final undoDose = feedback.undoDose;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(feedback.message),
        duration: const Duration(seconds: 4),
        // Snack bars with an action stay open by default in current Flutter;
        // a 4-second Undo window is enough here, so let it close itself.
        persist: false,
        action: undoDose == null
            ? null
            : SnackBarAction(
                label: 'Undo',
                onPressed: () =>
                    context.read<DashboardBloc>().add(DoseUndoRequested(undoDose)),
              ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: BlocConsumer<DashboardBloc, DashboardState>(
          listenWhen: (prev, curr) => curr.feedback != null && prev.feedback != curr.feedback,
          listener: (context, state) => _showFeedback(context, state.feedback!),
          builder: (context, state) {
            final snapshot = state.snapshot;
            final Widget body;
            if (state.status == DashboardStatus.failure) {
              body = MessageView.error(
                key: const ValueKey('error'),
                onRetry: () =>
                    context.read<DashboardBloc>().add(const DashboardRefreshRequested()),
              );
            } else if (state.status == DashboardStatus.loading || snapshot == null) {
              body = const DashboardSkeleton(key: ValueKey('loading'));
            } else {
              body = _DashboardContent(
                key: const ValueKey('ready'),
                state: state,
                snapshot: snapshot,
                onAddMedication: onAddMedication,
                onOpenAccount: onOpenAccount,
              );
            }
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: body,
            );
          },
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    super.key,
    required this.state,
    required this.snapshot,
    required this.onAddMedication,
    required this.onOpenAccount,
  });

  final DashboardState state;
  final DashboardSnapshot snapshot;
  final VoidCallback onAddMedication;
  final VoidCallback onOpenAccount;

  Future<void> _refresh(BuildContext context) {
    final bloc = context.read<DashboardBloc>()
      ..add(const DashboardRefreshRequested(userInitiated: true));
    // Keep the pull-to-refresh spinner until the sync finishes.
    return bloc.stream
        .firstWhere((s) => s.sync != SyncIndicator.syncing)
        .timeout(const Duration(seconds: 20), onTimeout: () => bloc.state);
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<DashboardBloc>();
    final next = snapshot.nextDose;
    final isEmpty = snapshot.total == 0;
    final text = Theme.of(context).textTheme;

    void take(TodayDose d) => bloc.add(DoseStatusChanged(d, DoseStatus.taken));
    void undo(TodayDose d) => bloc.add(DoseUndoRequested(d));

    return RefreshIndicator(
      onRefresh: () => _refresh(context),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.screen, AppSpace.lg, AppSpace.screen, 0),
            sliver: SliverList.list(
              children: [
                DaySummary(
                  snapshot: snapshot,
                  // The empty state has its own big button; avoid two.
                  onAddMedication: isEmpty ? null : onAddMedication,
                  onOpenAccount: onOpenAccount,
                ),
                SyncStatusLine(
                  sync: state.sync,
                  snapshot: snapshot,
                  onRetry: () => bloc.add(const DashboardRefreshRequested(userInitiated: true)),
                ),
                const ReminderBanner(),
                if (next != null) ...[
                  const SizedBox(height: AppSpace.xl),
                  NextDoseCard(
                    dose: next,
                    now: snapshot.now,
                    busy: state.isBusy(next),
                    onTake: () => take(next),
                    onSkip: () => bloc.add(DoseStatusChanged(next, DoseStatus.skipped)),
                  ),
                ],
              ],
            ),
          ),
          if (isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: MessageView.empty(onAddMedication: onAddMedication),
            )
          else
            for (final section in snapshot.sections)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.screen),
                sliver: SliverList.list(
                  children: [
                    const SizedBox(height: AppSpace.xxl),
                    Text(section.part.label, style: text.labelMedium),
                    const SizedBox(height: AppSpace.xs),
                    for (final dose in section.doses)
                      DoseRow(
                        key: ValueKey(dose.key),
                        dose: dose,
                        busy: state.isBusy(dose),
                        onTake: () => take(dose),
                        onUndo: () => undo(dose),
                      ),
                  ],
                ),
              ),
          // Room at the bottom so the last row clears the gesture bar / snack bar.
          SliverToBoxAdapter(
            child: SizedBox(height: AppSpace.section + MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }
}
