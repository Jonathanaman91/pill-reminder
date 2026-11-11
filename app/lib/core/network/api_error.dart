import 'package:dio/dio.dart';

import 'api_client.dart';

/// A failed API call turned into text the user can read. [fields] holds
/// per-field messages from the server, e.g. {'email': 'Already registered'}.
class ApiError implements Exception {
  const ApiError(this.message, {this.fields = const {}, this.isOffline = false});

  factory ApiError.from(Object error) {
    if (error is ApiError) return error;
    if (error is DioException) {
      if (error.isOffline) {
        return const ApiError(
          'No internet connection. Connect once to log in — after that the app works offline.',
          isOffline: true,
        );
      }
      final data = error.response?.data;
      if (data is Map) {
        final rawFields = data['fields'];
        return ApiError(
          data['error'] as String? ?? _fallback,
          fields: rawFields is Map
              ? {for (final e in rawFields.entries) '${e.key}': '${e.value}'}
              : const {},
        );
      }
    }
    return const ApiError(_fallback);
  }

  static const _fallback = 'Something went wrong. Please try again.';

  final String message;
  final Map<String, String> fields;
  final bool isOffline;

  @override
  String toString() => 'ApiError($message, $fields)';
}
