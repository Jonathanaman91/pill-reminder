import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../dashboard/data/dashboard_repository.dart';
import '../../dashboard/domain/today_dose.dart';

enum HistoryStatus { loading, ready, failure }

/// Taken, skipped and missed doses over a period.
class AdherenceSummary extends Equatable {
  const AdherenceSummary({required this.taken, required this.skipped, required this.missed});

  factory AdherenceSummary.of(Iterable<TodayDose> doses) => AdherenceSummary(
        taken: doses.where((d) => d.status == DoseStatus.taken).length,
        skipped: doses.where((d) => d.status == DoseStatus.skipped).length,
        missed: doses.where((d) => d.status == DoseStatus.missed).length,
      );

  final int taken;
  final int skipped;
  final int missed;

  int get total => taken + skipped + missed;

  /// Percentage of doses taken, or null when there were none.
  int? get percent => total == 0 ? null : (taken * 100 / total).round();

  @override
  List<Object?> get props => [taken, skipped, missed];
}

final class HistoryState extends Equatable {
  const HistoryState({this.status = HistoryStatus.loading, this.days = const []});

  final HistoryStatus status;

  /// Newest first; days with no doses scheduled are left out.
  final List<DoseDay> days;

  AdherenceSummary summaryFor(int lastDays, DateTime today) {
    final from = DateTime(today.year, today.month, today.day - lastDays);
    return AdherenceSummary.of([
      for (final d in days)
        if (!d.day.isBefore(from)) ...d.doses,
    ]);
  }

  @override
  List<Object?> get props => [status, days];
}

/// ViewModel for the History tab. Rebuilds whenever doses or medications
/// change, so marking a dose late on the Today tab shows up here too.
class HistoryCubit extends Cubit<HistoryState> {
  HistoryCubit(this._repository, {this.days = 30}) : super(const HistoryState()) {
    _changes = _repository.changes.listen((_) => load());
    load();
  }

  final DashboardRepository _repository;
  final int days;
  late final StreamSubscription<void> _changes;

  Future<void> load() async {
    try {
      final result = await _repository.history(days: days);
      if (!isClosed) emit(HistoryState(status: HistoryStatus.ready, days: result));
    } catch (_) {
      if (!isClosed && state.status != HistoryStatus.ready) {
        emit(const HistoryState(status: HistoryStatus.failure));
      }
    }
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
