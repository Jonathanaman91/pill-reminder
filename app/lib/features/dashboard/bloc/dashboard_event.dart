part of 'dashboard_bloc.dart';

sealed class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

/// Screen opened: start listening to the cache and kick off a sync.
final class DashboardStarted extends DashboardEvent {
  const DashboardStarted();
}

/// Pull-to-refresh (userInitiated) or an automatic retry.
final class DashboardRefreshRequested extends DashboardEvent {
  const DashboardRefreshRequested({this.userInitiated = false});

  final bool userInitiated;

  @override
  List<Object?> get props => [userInitiated];
}

/// "Mark as taken" or "Skip".
final class DoseStatusChanged extends DashboardEvent {
  const DoseStatusChanged(this.dose, this.status);

  final TodayDose dose;
  final DoseStatus status;

  @override
  List<Object?> get props => [dose, status];
}

/// "Undo" on the snack bar, or tapping a taken dose again.
final class DoseUndoRequested extends DashboardEvent {
  const DoseUndoRequested(this.dose);

  final TodayDose dose;

  @override
  List<Object?> get props => [dose];
}
