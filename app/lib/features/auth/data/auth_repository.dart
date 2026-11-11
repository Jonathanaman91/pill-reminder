import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../domain/auth_user.dart';

abstract interface class AuthRepository {
  /// Returns the saved user WITHOUT calling the server, so the app opens
  /// straight to the dashboard even with no signal.
  Future<AuthUser?> restoreSession();

  /// Throws [ApiError] with a readable message or per-field errors.
  Future<AuthUser> logIn({required String email, required String password});

  /// Throws [ApiError] with a readable message or per-field errors.
  Future<AuthUser> register({
    required String fullName,
    required String email,
    required String password,
  });

  /// Ends the session on the server (best effort) and wipes this phone's data.
  Future<void> logOut();

  /// Fires when the server rejects the session (e.g. refresh token expired).
  Stream<void> get sessionExpired;
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository({
    required Dio dio,
    required TokenStorage tokens,
    Future<void> Function()? clearLocalData,
  })  : _dio = dio,
        _tokens = tokens,
        _clearLocalData = clearLocalData;

  final Dio _dio;
  final TokenStorage _tokens;
  final Future<void> Function()? _clearLocalData;

  @override
  Stream<void> get sessionExpired => _tokens.sessionExpired;

  @override
  Future<AuthUser?> restoreSession() async {
    final refreshToken = await _tokens.readRefreshToken();
    final userJson = await _tokens.readUserJson();
    if (refreshToken == null || userJson == null) return null;
    try {
      return AuthUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
    } on FormatException {
      await _tokens.clear();
      return null;
    }
  }

  @override
  Future<AuthUser> logIn({required String email, required String password}) =>
      _authenticate('/auth/login', {'email': email.trim(), 'password': password});

  @override
  Future<AuthUser> register({
    required String fullName,
    required String email,
    required String password,
  }) =>
      _authenticate('/auth/register', {
        'fullName': fullName.trim(),
        'email': email.trim(),
        'password': password,
      });

  Future<AuthUser> _authenticate(String path, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(path, data: body);
      final data = res.data!;
      final user = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
      await _tokens.save(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      await _tokens.saveUserJson(jsonEncode(user.toJson()));
      return user;
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  @override
  Future<void> logOut() async {
    final refreshToken = await _tokens.readRefreshToken();
    if (refreshToken != null) {
      try {
        await _dio.post<void>(
          '/auth/logout',
          data: {'refreshToken': refreshToken},
          options: Options(sendTimeout: const Duration(seconds: 5)),
        );
      } on DioException {
        // Offline is fine: the server session simply expires on its own.
      }
    }
    await _tokens.clear();
    await _clearLocalData?.call();
  }
}
