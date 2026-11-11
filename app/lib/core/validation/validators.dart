/// Form rules shared by every screen. They match the server's zod rules in
/// backend/src/routes/auth.routes.js, so most mistakes are caught before
/// anything is sent — which matters when the signal is weak.
///
/// Each function returns null when the value is fine, or a message to show.
abstract final class Validators {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email.';
    if (!_email.hasMatch(v)) return 'Enter a valid email address.';
    return null;
  }

  static String? fullName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your name.';
    if (v.length < 2) return 'Enter your full name.';
    if (v.length > 120) return 'Use 120 characters or fewer.';
    return null;
  }

  /// Login only checks that something was typed; the server decides the rest.
  static String? passwordPresent(String? value) =>
      (value ?? '').isEmpty ? 'Enter your password.' : null;

  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter a password.';
    if (v.length < 8) return 'Use at least 8 characters.';
    if (v.length > 72) return 'Use 72 characters or fewer.';
    if (!RegExp('[A-Za-z]').hasMatch(v)) return 'Include at least one letter.';
    if (!RegExp('[0-9]').hasMatch(v)) return 'Include at least one number.';
    return null;
  }

  static String? Function(String?) matches(String Function() other) =>
      (value) => value != other() ? 'Passwords don’t match.' : null;

  // --- Add medication -------------------------------------------------------

  static final _medName = RegExp(r"^[\p{L}\p{N} .,'()/+\-]+$", unicode: true);

  static String? medicationName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter the medication name.';
    if (v.length < 2) return 'Use at least 2 characters.';
    if (v.length > 150) return 'Use 150 characters or fewer.';
    if (!_medName.hasMatch(v)) return 'Use letters, numbers and simple punctuation only.';
    return null;
  }

  /// Accepts "500", "0.5" or "2,5" (comma typed on some keyboards).
  static double? parseAmount(String? value) =>
      double.tryParse((value ?? '').trim().replaceAll(',', '.'));

  static String? strength(String? value) {
    final v = (value ?? '').trim().replaceAll(',', '.');
    if (v.isEmpty) return 'Enter the strength.';
    final amount = double.tryParse(v);
    if (amount == null) return 'Enter a number, e.g. 500 or 0.5.';
    if (amount <= 0) return 'Must be more than 0.';
    if (amount > 100000) return 'That looks too large.';
    if (v.contains('.') && v.split('.').last.length > 3) return 'Use up to 3 decimal places.';
    return null;
  }

  static String? instructions(String? value) =>
      (value ?? '').trim().length > 255 ? 'Use 255 characters or fewer.' : null;
}
