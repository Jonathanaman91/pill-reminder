// The app must never stay on the blank start-up screen, even if the saved
// login on the phone cannot be read.
import 'package:flutter_test/flutter_test.dart';
import 'package:pill_reminder/features/auth/bloc/auth_bloc.dart';
import 'package:pill_reminder/features/auth/data/auth_repository.dart';
import 'package:pill_reminder/features/auth/domain/auth_user.dart';

class _BrokenStorageRepo implements AuthRepository {
  @override
  Future<AuthUser?> restoreSession() async => throw Exception('BAD_DECRYPT');
  @override
  Stream<void> get sessionExpired => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('an unreadable saved session leads to the login screen', () async {
    final bloc = AuthBloc(repository: _BrokenStorageRepo())..add(const AuthStarted());
    final state = await bloc.stream.firstWhere((s) => s.status != AuthStatus.unknown);
    expect(state.status, AuthStatus.unauthenticated);
    await bloc.close();
  });
}
