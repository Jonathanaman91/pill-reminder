import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/profile_repository.dart';
import '../domain/health_profile.dart';

enum ProfileStatus { loading, editing, saving }

final class ProfileState extends Equatable {
  const ProfileState({
    this.status = ProfileStatus.loading,
    this.profile = HealthProfile.empty,
    this.saved = HealthProfile.empty,
    this.error,
  });

  final ProfileStatus status;

  /// What the form shows now.
  final HealthProfile profile;

  /// What is stored, to tell whether anything changed.
  final HealthProfile saved;
  final String? error;

  bool get changed => profile != saved;

  ProfileState copyWith({
    ProfileStatus? status,
    HealthProfile? profile,
    HealthProfile? saved,
    String? Function()? error,
  }) =>
      ProfileState(
        status: status ?? this.status,
        profile: profile ?? this.profile,
        saved: saved ?? this.saved,
        error: error != null ? error() : this.error,
      );

  @override
  List<Object?> get props => [status, profile, saved, error];
}

/// ViewModel for the health profile form.
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit(this._repository) : super(const ProfileState()) {
    _load();
  }

  final ProfileRepository _repository;

  Future<void> _load() async {
    final profile = await _repository.load();
    if (!isClosed) {
      emit(ProfileState(status: ProfileStatus.editing, profile: profile, saved: profile));
    }
  }

  void _edit(HealthProfile Function(HealthProfile p) change) =>
      emit(state.copyWith(profile: change(state.profile), error: () => null));

  void setDateOfBirth(DateTime? date) => _edit((p) => p.copyWith(dateOfBirth: () => date));

  void setGender(Gender? gender) => _edit((p) => p.copyWith(gender: () => gender));

  void toggleCondition(String condition) => _edit((p) {
        final has = p.conditions.any((c) => c.toLowerCase() == condition.toLowerCase());
        return p.copyWith(
          conditions: has
              ? p.conditions.where((c) => c.toLowerCase() != condition.toLowerCase()).toList()
              : [...p.conditions, condition],
        );
      });

  /// Adds a condition typed by the user. Returns a message if it can't.
  String? addCondition(String text) {
    final c = text.trim();
    if (c.length < 2) return 'Type the condition first.';
    if (c.length > 60) return 'Use 60 characters or fewer.';
    if (state.profile.conditions.length >= 20) return 'You can add up to 20 conditions.';
    if (state.profile.conditions.any((x) => x.toLowerCase() == c.toLowerCase())) {
      return '$c is already in your list.';
    }
    _edit((p) => p.copyWith(conditions: [...p.conditions, c]));
    return null;
  }

  void setAllergies(String text) => _edit((p) => p.copyWith(allergies: () => text));

  /// Returns true when saved.
  Future<bool> save() async {
    if (state.status == ProfileStatus.saving) return false;
    emit(state.copyWith(status: ProfileStatus.saving, error: () => null));
    try {
      await _repository.save(state.profile);
      emit(state.copyWith(status: ProfileStatus.editing, saved: state.profile));
      return true;
    } catch (_) {
      emit(state.copyWith(
        status: ProfileStatus.editing,
        error: () => 'Couldn’t save on this phone. Please try again.',
      ));
      return false;
    }
  }
}
