import 'package:flutter_test/flutter_test.dart';
import 'package:pill_reminder/features/facilities/bloc/nearby_cubit.dart';
import 'package:pill_reminder/features/facilities/data/facility_repository.dart';
import 'package:pill_reminder/features/facilities/data/location_service.dart';
import 'package:pill_reminder/features/facilities/domain/facility.dart';

Facility _f(String id, FacilityType type, Ownership own, {bool h24 = false, double d = 100}) => Facility(
  id: id,
  name: id,
  type: type,
  ownership: own,
  is24Hours: h24,
  latitude: 2.29,
  longitude: 111.83,
  distanceMeters: d,
  source: 'osm',
);

class _FakeLocation implements LocationService {
  LocationResult next = const LocationFound(2.29, 111.83);
  int settingsOpened = 0;

  @override
  Future<LocationResult> current() async => next;
  @override
  Future<void> openLocationSettings() async {
    settingsOpened++;
  }
  @override
  Future<void> openAppSettings() async {
    settingsOpened++;
  }
  @override
  double distanceBetween(double a, double b, double c, double d) => 0;
}

class _FakeRepo implements FacilityRepository {
  bool fail = false;

  @override
  Future<NearbyFacilities> nearby(double latitude, double longitude) async {
    if (fail) throw Exception('offline');
    return NearbyFacilities(fetchedAt: DateTime(2026), facilities: [
      _f('Farmasi', FacilityType.pharmacy, Ownership.private, h24: true, d: 200),
      _f('KK Oya', FacilityType.clinic, Ownership.public, d: 500),
      _f('Klinik Ting', FacilityType.clinic, Ownership.private, d: 800),
      _f('Hospital Sibu', FacilityType.hospital, Ownership.public, h24: true, d: 3000),
    ]);
  }
}

void main() {
  group('Facility', () {
    test('labels say government or private', () {
      expect(_f('a', FacilityType.clinic, Ownership.public).kindLabel, 'Government clinic');
      expect(_f('a', FacilityType.hospital, Ownership.private).kindLabel, 'Private hospital');
      expect(_f('a', FacilityType.pharmacy, Ownership.private).kindLabel, 'Pharmacy');
    });

    test('distance label', () {
      expect(_f('a', FacilityType.pharmacy, Ownership.private, d: 347).distanceLabel, '350 m');
      expect(_f('a', FacilityType.pharmacy, Ownership.private, d: 2440).distanceLabel, '2.4 km');
      expect(_f('a', FacilityType.pharmacy, Ownership.private, d: 12600).distanceLabel, '13 km');
    });

    test('JSON round trip', () {
      final f = _f('x', FacilityType.hospital, Ownership.public, h24: true);
      final back = Facility.fromJson(f.toJson());
      expect(back.kindLabel, 'Government hospital');
      expect(back.is24Hours, isTrue);
    });

    test('haversine: Sibu to Kapit is about 125 km in a straight line', () {
      final d = haversine(2.2870, 111.8305, 2.0167, 112.9333);
      expect(d, inInclusiveRange(115000, 130000));
    });
  });

  group('NearbyCubit', () {
    late _FakeLocation location;
    late _FakeRepo repo;
    late NearbyCubit cubit;

    setUp(() {
      location = _FakeLocation();
      repo = _FakeRepo();
      cubit = NearbyCubit(location: location, repository: repo);
    });
    tearDown(() => cubit.close());

    test('loads places nearest first', () async {
      await cubit.load();
      expect(cubit.state.status, NearbyStatus.ready);
      expect(cubit.state.visible.first.name, 'Farmasi');
    });

    test('filters by where a prescription comes from', () async {
      await cubit.load();
      cubit.setFilter(FacilityFilter.governmentClinic);
      expect(cubit.state.visible.map((f) => f.name), ['KK Oya']);
      cubit.setFilter(FacilityFilter.privateClinic);
      expect(cubit.state.visible.map((f) => f.name), ['Klinik Ting']);
      cubit
        ..setFilter(FacilityFilter.all)
        ..toggleOpen24();
      expect(cubit.state.visible.map((f) => f.name), ['Farmasi', 'Hospital Sibu']);
    });

    test('location problems become clear states', () async {
      location.next = const LocationServiceOff();
      await cubit.load();
      expect(cubit.state.status, NearbyStatus.locationOff);

      location.next = const LocationDenied(permanently: true);
      await cubit.load();
      expect(cubit.state.status, NearbyStatus.permissionDeniedForever);
      await cubit.fixLocation();
      expect(location.settingsOpened, 1);

      location.next = const LocationFound(2.29, 111.83);
      await cubit.onResume(); // back from Settings → retries
      expect(cubit.state.status, NearbyStatus.ready);
    });

    test('missing manifest permissions show a message instead of hanging', () async {
      location.next = const LocationNotConfigured();
      await cubit.load();
      expect(cubit.state.status, NearbyStatus.locationNotConfigured);
    });

    test('a failed refresh keeps the places already shown', () async {
      await cubit.load();
      repo.fail = true;
      await cubit.load();
      expect(cubit.state.status, NearbyStatus.ready);
      expect(cubit.state.visible, isNotEmpty);
      expect(cubit.state.error, isNotNull);
    });

    test('first load failing shows the error screen', () async {
      repo.fail = true;
      await cubit.load();
      expect(cubit.state.status, NearbyStatus.failure);
    });
  });
}