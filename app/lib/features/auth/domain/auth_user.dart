import 'package:equatable/equatable.dart';

class AuthUser extends Equatable {
  const AuthUser({
    required this.id,
    required this.email,
    required this.fullName,
    this.role = 'user',
  });

  /// Someone using the app without an account. Everything they add stays in
  /// this phone's database and is never sent to the server, until they
  /// create an account or log in (then it is uploaded to that account).
  static const guest = AuthUser(id: guestId, email: '', fullName: 'Guest', role: 'guest');
  static const guestId = 'guest';

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String,
        fullName: json['fullName'] as String,
        role: json['role'] as String? ?? 'user',
      );

  final String id;
  final String email;
  final String fullName;
  final String role;

  bool get isGuest => id == guestId;

  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;

  Map<String, dynamic> toJson() =>
      {'id': id, 'email': email, 'fullName': fullName, 'role': role};

  @override
  List<Object?> get props => [id, email, fullName, role];
}
