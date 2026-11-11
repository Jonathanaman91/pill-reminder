part of 'dashboard_bloc.dart';

enum DashboardStatus {
  /// First launch and nothing cached yet → skeleton.
  loading,

  /// We have a snapshot to show (from cache or freshly synced).
  ready,

  /// Nothing cached AND the first sync failed → full-screen retry.
  failure,
}

enum SyncIndicator { idle, syncing, offline, error }

/// A one-time message for the snack bar. Each one gets a new [id], so the
/// same text shown twice still counts as a new message.
final class DashboardFeedback extends Equatable {
  const DashboardFeedback({required this.id, required this.message, this.undoDose});

  final int id;
  final String message;
  final TodayDose? undoDose;

  @override
  List<Object?> get props => [id];
}

final class DashboardState extends Equatable {
  const DashboardState({
    this.status = DashboardStatus.loading,
    this.snapshot,
    this.sync = SyncIndicator.idle,
    this.busyDoseKeys = const {},
    this.feedback,
  });

  final DashboardStatus status;
  final DashboardSnapshot? snapshot;
  final SyncIndicator sync;

  /// Doses being saved right now; their buttons show a spinner.
  final Set<String> busyDoseKeys;
  final DashboardFeedback? feedback;

  bool isBusy(TodayDose dose) => busyDoseKeys.contains(dose.key);

  DashboardState copyWith({
    DashboardStatus? status,
    DashboardSnapshot? snapshot,
    SyncIndicator? sync,
    Set<String>? busyDoseKeys,
    DashboardFeedback? feedback,
  }) =>
      DashboardState(
        status: status ?? this.status,
        snapshot: snapshot ?? this.snapshot,
        sync: sync ?? this.sync,
        busyDoseKeys: busyDoseKeys ?? this.busyDoseKeys,
        feedback: feedback ?? this.feedback,
      );

  @override
  List<Object?> get props => [status, snapshot, sync, busyDoseKeys, feedback];
}
