import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_pusher.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../domain/health_profile.dart';

abstract interface class ProfileRepository {
  Future<HealthProfile> load();

  /// Saved on the phone first (works offline), uploaded at the next sync.
  Future<void> save(HealthProfile profile);
}

/// Keeps the profile in the SQLite `meta` table, so it works offline, is
/// wiped on logout with everything else, and stays on the phone for guests.
class ProfileLocalStore {
  ProfileLocalStore(AppDatabase database) : _db = database.db;

  final Database _db;
  static const _key = 'health_profile';
  static const _pendingKey = 'health_profile_pending'; // "1" = not uploaded yet

  Future<String?> _get(String key) async {
    final rows = await _db.query('meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _put(String key, String? value) =>
      _db.insert('meta', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<HealthProfile> read() async {
    final json = await _get(_key);
    if (json == null) return HealthProfile.empty;
    try {
      return HealthProfile.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } on Object {
      return HealthProfile.empty;
    }
  }

  Future<void> write(HealthProfile profile, {required bool pending}) async {
    await _put(_key, jsonEncode(profile.toJson()));
    await _put(_pendingKey, pending ? '1' : null);
  }

  Future<bool> isPending() async => await _get(_pendingKey) == '1';
}

class OfflineFirstProfileRepository implements ProfileRepository {
  OfflineFirstProfileRepository({required ProfileLocalStore local, required DashboardRepository dashboard})
      : _local = local,
        _dashboard = dashboard;

  final ProfileLocalStore _local;
  final DashboardRepository _dashboard;

  @override
  Future<HealthProfile> load() => _local.read();

  @override
  Future<void> save(HealthProfile profile) async {
    await _local.write(profile, pending: true);
    await _dashboard.onLocalDataChanged(); // starts a sync, which uploads it
  }
}

/// Part of every sync: uploads a changed profile, otherwise downloads the
/// server's copy (e.g. after logging in on a new phone).
class ProfileSyncPusher implements SyncPusher {
  ProfileSyncPusher({required ProfileLocalStore local, required Dio dio})
      : _local = local,
        _dio = dio;

  final ProfileLocalStore _local;
  final Dio _dio;

  @override
  Future<void> pushPending() async {
    try {
      if (await _local.isPending()) {
        final sent = await _local.read();
        await _dio.put<void>('/me/profile', data: sent.toJson());
        // Only clear the flag if nothing was edited while uploading.
        if (await _local.read() == sent) await _local.write(sent, pending: false);
      } else {
        final res = await _dio.get<Map<String, dynamic>>('/me/profile');
        final server = HealthProfile.fromJson(res.data!['profile'] as Map<String, dynamic>);
        if (!await _local.isPending()) await _local.write(server, pending: false);
      }
    } on DioException catch (e) {
      if (e.isOffline) rethrow; // stop; everything retries next sync
      // An older server without /me/profile, or a refused value: keep the
      // phone's copy and let the rest of the sync carry on.
      developer.log('Profile sync skipped: ${e.response?.statusCode}', name: 'ProfileSyncPusher');
    }
  }
}

/// In-memory profile for demo mode.
class DemoProfileRepository implements ProfileRepository {
  HealthProfile _profile = HealthProfile(
    dateOfBirth: DateTime(1958, 4, 12),
    gender: Gender.female,
    conditions: const ['Diabetes', 'High blood pressure'],
    allergies: 'Penicillin',
  );

  @override
  Future<HealthProfile> load() async => _profile;

  @override
  Future<void> save(HealthProfile profile) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _profile = profile;
  }
}
