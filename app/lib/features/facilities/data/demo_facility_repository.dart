import '../domain/facility.dart';
import 'facility_repository.dart';

/// Sample places placed around wherever the phone is, so the map can be shown
/// without the backend. The screen labels these as sample places.
class DemoFacilityRepository implements FacilityRepository {
  // (name, type, ownership, 24h, metres north, metres east, phone)
  static const _samples = [
    ('Farmasi Harmoni', FacilityType.pharmacy, Ownership.private, false, 350.0, 220.0, '084-210 111'),
    ('Klinik Kesihatan Bandar Baru', FacilityType.clinic, Ownership.public, false, -900.0, 600.0, '084-210 222'),
    ('Klinik Dr. Lim', FacilityType.clinic, Ownership.private, false, 620.0, -480.0, '084-210 333'),
    ('Hospital Daerah', FacilityType.hospital, Ownership.public, true, -2100.0, -1500.0, '084-210 444'),
    ('Farmasi 24 Jam Sentosa', FacilityType.pharmacy, Ownership.private, true, 1500.0, 1900.0, null),
    ('Pusat Perubatan Rejang', FacilityType.hospital, Ownership.private, true, 3200.0, -2600.0, '084-210 555'),
    ('Klinik Desa Sungai', FacilityType.clinic, Ownership.public, false, -4300.0, 3800.0, null),
    ('Klinik Keluarga Wong', FacilityType.clinic, Ownership.private, false, 2600.0, 400.0, '084-210 666'),
  ];

  @override
  Future<NearbyFacilities> nearby(double latitude, double longitude) async {
    await Future<void>.delayed(const Duration(milliseconds: 900)); // show the skeleton
    const metresPerDegree = 111320.0;
    final facilities = [
      for (final (i, s) in _samples.indexed)
        () {
          final (name, type, ownership, h24, north, east, phone) = s;
          final lat = latitude + north / metresPerDegree;
          final lng = longitude + east / metresPerDegree;
          return Facility(
            id: 'demo-$i',
            name: name,
            type: type,
            ownership: ownership,
            is24Hours: h24,
            latitude: lat,
            longitude: lng,
            distanceMeters: haversine(latitude, longitude, lat, lng),
            source: 'demo',
            phone: phone,
            openingHours: h24 ? '24/7' : 'Mo-Fr 08:00-17:00',
          );
        }(),
    ]..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    return NearbyFacilities(facilities: facilities, fetchedAt: DateTime.now(), isDemo: true);
  }
}
