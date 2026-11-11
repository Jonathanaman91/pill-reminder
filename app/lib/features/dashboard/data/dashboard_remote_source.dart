import 'package:dio/dio.dart';

/// Response of `GET /api/v1/sync?since=<iso>` — every row the user owns that
/// changed after `since` (all rows when `since` is missing), plus the streak.
class SyncPayload {
  const SyncPayload({
    required this.serverTime,
    required this.medications,
    required this.schedules,
    required this.doseLogs,
    required this.streakBeforeToday,
    required this.bestStreak,
    required this.streakAsOf,
  });

  factory SyncPayload.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> rows(String key) =>
        (json[key] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final streak = json['streak'] as Map<String, dynamic>? ?? const {};
    return SyncPayload(
      serverTime: json['serverTime'] as String,
      medications: rows('medications'),
      schedules: rows('schedules'),
      doseLogs: rows('doseLogs'),
      streakBeforeToday: streak['daysBeforeToday'] as int? ?? 0,
      bestStreak: streak['best'] as int? ?? 0,
      streakAsOf: streak['asOf'] as String?, // yyyy-MM-dd in the user's timezone
    );
  }

  final String serverTime;
  final List<Map<String, dynamic>> medications;
  final List<Map<String, dynamic>> schedules;
  final List<Map<String, dynamic>> doseLogs;
  final int streakBeforeToday;
  final int bestStreak;
  final String? streakAsOf;
}

class DashboardRemoteSource {
  DashboardRemoteSource(this._dio);

  final Dio _dio;

  Future<SyncPayload> pull({String? since}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/sync',
      queryParameters: {if (since != null) 'since': since},
    );
    return SyncPayload.fromJson(res.data!);
  }

  /// `POST /api/v1/dose-logs/batch` — the server upserts on
  /// (schedule_id, scheduled_at), so re-sending after a dropped connection is safe.
  Future<void> pushDoseLogs(List<Map<String, Object?>> localRows) async {
    String? iso(Object? ms) =>
        ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms as int).toUtc().toIso8601String();

    await _dio.post<void>('/dose-logs/batch', data: {
      'logs': [
        for (final r in localRows)
          {
            'id': r['id'],
            'scheduleId': r['schedule_id'],
            'userMedicationId': r['medication_id'],
            'scheduledAt': iso(r['scheduled_at']),
            'status': r['status'],
            'takenAt': iso(r['taken_at']),
            'updatedAt': iso(r['updated_at']),
            'deleted': r['deleted'] == 1,
          },
      ],
    });
  }
}
