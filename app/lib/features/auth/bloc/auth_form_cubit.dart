import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/network/api_error.dart';
import '../data/auth_repository.dart';
import '../domain/auth_user.dart';

final class AuthFormState extends Equatable {
  const AuthFormState({this.submitting = false, this.error, this.fieldErrors = const {}});

  final bool submitting;

  /// General error shown above the button (wrong password, no internet).
  final String? error;

  /// Server errors for one field, shown under that text box.
  final Map<String, String> fieldErrors;

  @override
  List<Object?> get props => [submitting, error, fieldErrors];
}

/// ViewModel for the login and register forms. The session itself lives in
/// AuthBloc; this cubit only tracks "sending…" and the errors to display.
class AuthFormCubit extends Cubit<AuthFormState> {
  AuthFormCubit(this._repository) : super(const AuthFormState());

  final AuthRepository _repository;

  Future<AuthUser?> logIn({required String email, required String password}) =>
      _submit(() => _repository.logIn(email: email, password: password));

  Future<AuthUser?> register({
    required String fullName,
    required String email,
    required String password,
  }) =>
      _submit(() => _repository.register(fullName: fullName, email: email, password: password));

  /// Called when the user edits a field, so an old server error disappears.
  void clearFieldError(String field) {
    if (!state.fieldErrors.containsKey(field) && state.error == null) return;
    emit(AuthFormState(
      submitting: state.submitting,
      fieldErrors: Map.of(state.fieldErrors)..remove(field),
    ));
  }

  Future<AuthUser?> _submit(Future<AuthUser> Function() action) async {
    if (state.submitting) return null; // ignore double taps
    emit(const AuthFormState(submitting: true));
    try {
      final user = await action();
      emit(const AuthFormState());
      return user;
    } catch (e) {
      final error = ApiError.from(e);
      emit(AuthFormState(
        // Field errors already explain the problem; skip the general sentence.
        error: error.fields.isEmpty ? error.message : null,
        fieldErrors: error.fields,
      ));
      return null;
    }
  }
}
