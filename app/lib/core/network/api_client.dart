import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the JWT pair and the logged-in user in the Android Keystore
/// (encrypted), never in plain SharedPreferences.
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final _expired = StreamController<void>.broadcast();

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _userKey = 'session_user';

  /// Fires when the server rejects the refresh token, i.e. the user must
  /// log in again (password changed, session revoked by an admin, 30 days passed).
  Stream<void> get sessionExpired => _expired.stream;

  Future<String?> readAccessToken() => _storage.read(key: _accessKey);
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);
  Future<String?> readUserJson() => _storage.read(key: _userKey);

  Future<void> save({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  Future<void> saveUserJson(String json) => _storage.write(key: _userKey, value: json);

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userKey);
  }

  Future<void> expireSession() async {
    await clear();
    if (!_expired.isClosed) _expired.add(null);
  }
}

class ApiClient {
  ApiClient({required String baseUrl, required TokenStorage tokens})
      : dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            // Short connect timeout: on a weak rural signal we would rather
            // fall back to the cached schedule quickly than make the user wait.
            connectTimeout: const Duration(seconds: 8),
            // Long receive timeout: a free Render server that has been asleep
            // takes up to a minute to answer its first request. Syncing runs in
            // the background, so waiting doesn't block the screen.
            receiveTimeout: const Duration(seconds: 75),
            contentType: Headers.jsonContentType,
          ),
        ) {
    dio.interceptors.add(_AuthInterceptor(tokens: tokens, baseUrl: baseUrl, dio: dio));
  }

  final Dio dio;
}

/// Adds `Authorization: Bearer <access token>` to each request. When the
/// server answers 401 (token expired), it swaps the refresh token for a new
/// pair once and replays the original request. QueuedInterceptor makes sure
/// several requests failing at the same time only trigger ONE refresh.
class _AuthInterceptor extends QueuedInterceptor {
  _AuthInterceptor({required this.tokens, required String baseUrl, required this.dio})
      : _refreshDio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 8),
          contentType: Headers.jsonContentType,
        ));

  final TokenStorage tokens;
  final Dio dio;
  final Dio _refreshDio; // separate instance, so a refresh never loops back here

  static const _retriedFlag = 'auth_retried';

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await tokens.readAccessToken();
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final isAuthRoute = err.requestOptions.path.startsWith('/auth/');
    final alreadyRetried = err.requestOptions.extra[_retriedFlag] == true;
    final refreshToken = await tokens.readRefreshToken();
    if (err.response?.statusCode != 401 ||
        isAuthRoute ||
        alreadyRetried ||
        refreshToken == null) {
      handler.next(err);
      return;
    }

    try {
      final res = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final body = res.data!;
      await tokens.save(
        accessToken: body['accessToken'] as String,
        refreshToken: body['refreshToken'] as String,
      );
      final retry = err.requestOptions..extra[_retriedFlag] = true;
      handler.resolve(await dio.fetch<dynamic>(retry));
    } on DioException catch (refreshError) {
      // Only log the user out when the server REJECTED the refresh token.
      // If the refresh failed because the phone is offline, keep the session:
      // the app must keep working with no signal.
      final status = refreshError.response?.statusCode;
      if (status == 401 || status == 403) await tokens.expireSession();
      handler.next(err);
    }
  }
}

extension DioOffline on DioException {
  /// True when the request failed because there is no usable connection,
  /// as opposed to the server answering with an error.
  bool get isOffline => switch (type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.connectionError =>
          true,
        DioExceptionType.unknown => error is SocketException,
        _ => false,
      };
}
