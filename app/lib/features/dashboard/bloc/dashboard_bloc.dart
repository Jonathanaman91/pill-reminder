import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/dashboard_repository.dart';
import '../domain/dashboard_snapshot.dart';
import '../domain/today_dose.dart';

part 'dashboard_event.dart';
part 'dashboard_state.dart';

/// Data flow (one direction only):
///
///   UI ──event──▶ DashboardBloc ──▶ Repository ──▶ SQLite (+ API in background)
///   UI ◀──state── DashboardBloc ◀── watchToday() stream ◀── SQLite
///
/// The BLoC never edits the dose list itself. It asks the repository to save,
/// and the new list arrives through the stream. Because of this, the screen
/// shows exactly what is stored on the phone, online or offline.
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  DashboardBloc({required DashboardRepository repository})
      : _repository = repository,
        super(const DashboardState()) {
    on<DashboardStarted>(_onStarted);
    on<DashboardRefreshRequested>(_onRefreshRequested);
    on<DoseStatusChanged>(_onDoseStatusChanged);
    on<DoseUndoRequested>(_onDoseUndoRequested);
  }

  final DashboardRepository _repository;
  int _feedbackSeq = 0;

  Future<void> _onStarted(DashboardStarted event, Emitter<DashboardState> emit) async {
    add(const DashboardRefreshRequested());

    // Stays subscribed for as long as the BLoC lives.
    await emit.forEach<DashboardSnapshot>(
      _repository.watchToday(),
      onData: (snapshot) => state.copyWith(
        snapshot: snapshot,
        status: snapshot.hasCache ? DashboardStatus.ready : state.status,
      ),
      onError: (_, _) => state.copyWith(
        status: state.snapshot == null ? DashboardStatus.failure : state.status,
        sync: SyncIndicator.error,
      ),
    );
  }

  Future<void> _onRefreshRequested(
    DashboardRefreshRequested event,
    Emitter<DashboardState> emit,
  ) async {
    emit(state.copyWith(
      sync: SyncIndicator.syncing,
      // Leave the error screen while retrying, so the skeleton shows again.
      status: state.status == DashboardStatus.failure ? DashboardStatus.loading : null,
    ));

    final outcome = await _repository.sync();
    final hasCache = state.snapshot?.hasCache ?? false;

    switch (outcome) {
      case SyncOutcome.synced:
        // The fresh snapshot arrives through watchToday() and sets status.
        emit(state.copyWith(sync: SyncIndicator.idle));
      case SyncOutcome.offline:
      case SyncOutcome.failed:
        final offline = outcome == SyncOutcome.offline;
        emit(state.copyWith(
          sync: offline ? SyncIndicator.offline : SyncIndicator.error,
          status: hasCache ? null : DashboardStatus.failure,
          feedback: event.userInitiated && hasCache
              ? _feedback(offline
                  ? 'You’re offline. Showing your saved schedule.'
                  : 'Couldn’t reach the server. Try again soon.')
              : null,
        ));
    }
  }

  Future<void> _onDoseStatusChanged(
    DoseStatusChanged event,
    Emitter<DashboardState> emit,
  ) async {
    final key = event.dose.key;
    if (state.busyDoseKeys.contains(key)) return; // ignore double taps

    emit(state.copyWith(busyDoseKeys: {...state.busyDoseKeys, key}));
    try {
      final saved = await _repository.recordDose(event.dose, event.status);
      final verb = event.status == DoseStatus.taken ? 'marked as taken' : 'skipped';
      emit(state.copyWith(
        busyDoseKeys: state.busyDoseKeys.difference({key}),
        feedback: _feedback('${event.dose.name} $verb', undoDose: saved),
      ));
    } catch (_) {
      emit(state.copyWith(
        busyDoseKeys: state.busyDoseKeys.difference({key}),
        feedback: _feedback('Couldn’t save that dose. Please try again.'),
      ));
    }
  }

  Future<void> _onDoseUndoRequested(
    DoseUndoRequested event,
    Emitter<DashboardState> emit,
  ) async {
    try {
      await _repository.undoDose(event.dose);
    } catch (_) {
      emit(state.copyWith(feedback: _feedback('Couldn’t undo. Please try again.')));
    }
  }

  DashboardFeedback _feedback(String message, {TodayDose? undoDose}) =>
      DashboardFeedback(id: ++_feedbackSeq, message: message, undoDose: undoDose);
}
