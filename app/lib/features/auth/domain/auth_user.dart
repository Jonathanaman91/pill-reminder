import 'package:equatable/equatable.dart';

class AuthUser extends Equatable {
  const AuthUser({
    required this.id,
    required this.email,
    required this.fullName,
    this.role = 'user',
  });

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

  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;

  Map<String, dynamic> toJson() =>
      {'id': id, 'email': email, 'fullName': fullName, 'role': role};

  @override
  List<Object?> get props => [id, email, fullName, role];
}
