import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/auth_repository.dart';
import '../domain/auth_user.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------
sealed class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// App launched: check the phone for a saved session.
final class AuthStarted extends AuthEvent {
  const AuthStarted();
}

/// The login or register form succeeded.
final class AuthLoggedIn extends AuthEvent {
  const AuthLoggedIn(this.user, {this.notice});

  final AuthUser user;
  final String? notice;

  @override
  List<Object?> get props => [user, notice];
}

final class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

final class _AuthSessionExpired extends AuthEvent {
  const _AuthSessionExpired();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------
enum AuthStatus { unknown, authenticated, unauthenticated }

/// One-time message for a snack bar (new [id] each time).
final class AuthNotice extends Equatable {
  const AuthNotice(this.id, this.message);

  final int id;
  final String message;

  @override
  List<Object?> get props => [id];
}

final class AuthState extends Equatable {
  const AuthState({this.status = AuthStatus.unknown, this.user, this.notice});

  final AuthStatus status;
  final AuthUser? user;
  final AuthNotice? notice;

  @override
  List<Object?> get props => [status, user, notice];
}

// ---------------------------------------------------------------------------
// BLoC — owns "who is logged in" for the whole app.
// ---------------------------------------------------------------------------
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required AuthRepository repository})
      : _repository = repository,
        super(const AuthState()) {
    on<AuthStarted>(_onStarted);
    on<AuthLoggedIn>(_onLoggedIn);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<_AuthSessionExpired>(_onSessionExpired);

    _expiredSub = _repository.sessionExpired.listen((_) => add(const _AuthSessionExpired()));
  }

  final AuthRepository _repository;
  late final StreamSubscription<void> _expiredSub;
  int _noticeSeq = 0;

  Future<void> _onStarted(AuthStarted event, Emitter<AuthState> emit) async {
    final user = await _repository.restoreSession();
    emit(AuthState(
      status: user == null ? AuthStatus.unauthenticated : AuthStatus.authenticated,
      user: user,
    ));
  }

  void _onLoggedIn(AuthLoggedIn event, Emitter<AuthState> emit) {
    emit(AuthState(
      status: AuthStatus.authenticated,
      user: event.user,
      notice: event.notice == null ? null : AuthNotice(++_noticeSeq, event.notice!),
    ));
  }

  Future<void> _onLogoutRequested(AuthLogoutRequested event, Emitter<AuthState> emit) async {
    await _repository.logOut();
    emit(const AuthState(status: AuthStatus.unauthenticated));
  }

  Future<void> _onSessionExpired(_AuthSessionExpired event, Emitter<AuthState> emit) async {
    if (state.status != AuthStatus.authenticated) return;
    await _repository.logOut();
    emit(AuthState(
      status: AuthStatus.unauthenticated,
      notice: AuthNotice(++_noticeSeq, 'Your session ended. Please log in again.'),
    ));
  }

  @override
  Future<void> close() async {
    await _expiredSub.cancel();
    return super.close();
  }
}
