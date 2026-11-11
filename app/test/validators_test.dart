import 'package:flutter_test/flutter_test.dart';
import 'package:pill_reminder/core/validation/validators.dart';

void main() {
  test('email', () {
    expect(Validators.email(''), 'Enter your email.');
    expect(Validators.email('jon@'), isNotNull);
    expect(Validators.email('jon@uts.edu.my'), isNull);
    expect(Validators.email('  jon@uts.edu.my  '), isNull);
  });

  test('new password needs 8+ chars, a letter and a number', () {
    expect(Validators.newPassword('abc1'), 'Use at least 8 characters.');
    expect(Validators.newPassword('abcdefgh'), 'Include at least one number.');
    expect(Validators.newPassword('12345678'), 'Include at least one letter.');
    expect(Validators.newPassword('Passw0rd'), isNull);
  });

  test('confirm password must match', () {
    final check = Validators.matches(() => 'Passw0rd');
    expect(check('Passw0rd'), isNull);
    expect(check('Passw0rd!'), isNotNull);
  });

  test('full name', () {
    expect(Validators.fullName(' '), 'Enter your name.');
    expect(Validators.fullName('J'), 'Enter your full name.');
    expect(Validators.fullName('Jonathan'), isNull);
  });
}
