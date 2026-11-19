import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/medication_repository.dart';
import '../domain/medication.dart';

enum MedicationsStatus { loading, ready, failure }

/// A one-off message for the snack bar. [id] makes two identical messages in
/// a row count as different, so the second one is shown too.
typedef MedicationsFeedback = ({int id, String message});

final class MedicationsState extends Equatable {
  const MedicationsState({
    this.status = MedicationsStatus.loading,
    this.medications = const [],
    this.deletingIds = const {},
    this.feedback,
  });

  final MedicationsStatus status;
  final List<Medication> medications;

  /// Rows that show a spinner because their delete is being saved.
  final Set<String> deletingIds;
  final MedicationsFeedback? feedback;

  MedicationsState copyWith({
    MedicationsStatus? status,
    List<Medication>? medications,
    Set<String>? deletingIds,
    MedicationsFeedback? feedback,
  }) =>
      MedicationsState(
        status: status ?? this.status,
        medications: medications ?? this.medications,
        deletingIds: deletingIds ?? this.deletingIds,
        feedback: feedback ?? this.feedback,
      );

  @override
  List<Object?> get props => [status, medications, deletingIds, feedback];
}

/// ViewModel for the Medications tab: the full list of saved medications,
/// kept fresh whenever one is added, edited, deleted or synced.
class MedicationsCubit extends Cubit<MedicationsState> {
  MedicationsCubit(this._repository) : super(const MedicationsState()) {
    _changes = _repository.changes.listen((_) => load());
    load();
  }

  final MedicationRepository _repository;
  late final StreamSubscription<void> _changes;
  int _feedbackSeq = 0;

  Future<void> load() async {
    try {
      final medications = await _repository.all();
      if (isClosed) return;
      emit(state.copyWith(status: MedicationsStatus.ready, medications: medications));
    } catch (_) {
      if (isClosed) return;
      // Keep showing the last good list if there is one.
      if (state.status != MedicationsStatus.ready) {
        emit(state.copyWith(status: MedicationsStatus.failure));
      }
    }
  }

  void retry() {
    emit(state.copyWith(status: MedicationsStatus.loading));
    load();
  }

  /// The screen asks the user to confirm before calling this.
  Future<void> delete(Medication medication) async {
    final id = medication.id;
    if (state.deletingIds.contains(id)) return; // ignore double taps

    emit(state.copyWith(deletingIds: {...state.deletingIds, id}));
    String message;
    try {
      await _repository.delete(id);
      message = '${medication.name} deleted';
    } catch (_) {
      message = 'Couldn’t delete ${medication.name}. Please try again.';
    }
    if (isClosed) return;
    emit(state.copyWith(
      deletingIds: state.deletingIds.difference({id}),
      feedback: (id: ++_feedbackSeq, message: message),
    ));
    await load();
  }

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }
}
