import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_error.dart';
import '../domain/facility.dart';

class NearbyFacilities {
  const NearbyFacilities({
    required this.facilities,
    required this.fetchedAt,
    this.fromCache = false,
    this.partial = false,
    this.isDemo = false,
  });

  final List<Facility> facilities; // nearest first
  final DateTime fetchedAt;

  /// No connection: these are the places saved from the last search.
  final bool fromCache;

  /// The server couldn't reach OpenStreetMap; only admin-added places.
  final bool partial;
  final bool isDemo;
}

abstract interface class FacilityRepository {
  /// Throws [ApiError] if offline AND nothing has been saved before.
  Future<NearbyFacilities> nearby(double latitude, double longitude);
}

/// Online: asks the API and saves the answer in SQLite.
/// Offline: shows the saved answer, with distances recalculated from where
/// the user is now (GPS itself works without internet).
class CachedFacilityRepository implements FacilityRepository {
  CachedFacilityRepository({required Dio dio, required AppDatabase database})
      : _dio = dio,
        _db = database.db;

  final Dio _dio;
  final Database _db;
  static const _cacheKey = 'facilities_cache';
  static const radiusMeters = 10000;

  @override
  Future<NearbyFacilities> nearby(double latitude, double longitude) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/facilities/nearby',
        queryParameters: {
          'lat': latitude.toStringAsFixed(5),
          'lng': longitude.toStringAsFixed(5),
          'radius': radiusMeters,
        },
        // The server may need ~1 min to wake up (free hosting) and then up to
        // 24 s to ask OpenStreetMap. Wait longer than that, so we get its
        // answer instead of giving up first.
        options: Options(receiveTimeout: const Duration(seconds: 100)),
      );
      final data = res.data!;
      final now = DateTime.now();
      final facilities = [
        for (final f in data['facilities'] as List<dynamic>)
          Facility.fromJson(f as Map<String, dynamic>),
      ];
      await _db.insert(
        'meta',
        {
          'key': _cacheKey,
          'value': jsonEncode({
            'fetchedAt': now.toIso8601String(),
            'facilities': [for (final f in facilities) f.toJson()],
          }),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return NearbyFacilities(
        facilities: facilities,
        fetchedAt: now,
        partial: data['partial'] == true,
      );
    } on DioException catch (e) {
      final cached = await _readCache(latitude, longitude);
      if (cached != null) return cached;
      throw ApiError.from(e);
    }
  }

  Future<NearbyFacilities?> _readCache(double lat, double lng) async {
    final rows = await _db.query('meta', where: 'key = ?', whereArgs: [_cacheKey]);
    if (rows.isEmpty) return null;
    final json = jsonDecode(rows.first['value'] as String) as Map<String, dynamic>;
    final facilities = [
      for (final f in json['facilities'] as List<dynamic>)
        Facility.fromJson(f as Map<String, dynamic>),
    ].map((f) => f.withDistance(haversine(lat, lng, f.latitude, f.longitude))).toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return NearbyFacilities(
      facilities: facilities,
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      fromCache: true,
    );
  }
}

/// Straight-line distance in metres.
double haversine(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}
