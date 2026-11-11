import 'dart:async';

import '../../../core/network/api_error.dart';
import '../domain/auth_user.dart';
import 'auth_repository.dart';

/// Lets you try the login and register screens without the backend.
///   • Any valid email + password logs in.
///   • Password "wrongpass1" shows the "incorrect password" error.
///   • Registering taken@example.com shows the "already registered" error.
///   • Email offline@example.com shows the no-internet error.
class DemoAuthRepository implements AuthRepository {
  final _expired = StreamController<void>.broadcast();
  AuthUser? _user;

  @override
  Stream<void> get sessionExpired => _expired.stream;

  @override
  Future<AuthUser?> restoreSession() async => _user;

  @override
  Future<AuthUser> logIn({required String email, required String password}) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    _throwIfOffline(email);
    if (password == 'wrongpass1') throw const ApiError('Incorrect email or password.');
    return _user = AuthUser(id: 'demo-user', email: email.trim(), fullName: 'Demo User');
  }

  @override
  Future<AuthUser> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    _throwIfOffline(email);
    if (email.trim().toLowerCase() == 'taken@example.com') {
      throw const ApiError('That email is already registered.',
          fields: {'email': 'That email is already registered. Try logging in.'});
    }
    return _user = AuthUser(id: 'demo-user', email: email.trim(), fullName: fullName.trim());
  }

  @override
  Future<void> logOut() async {
    _user = null;
  }

  void _throwIfOffline(String email) {
    if (email.trim().toLowerCase() == 'offline@example.com') {
      throw const ApiError(
        'No internet connection. Connect once to log in — after that the app works offline.',
        isOffline: true,
      );
    }
  }
}
