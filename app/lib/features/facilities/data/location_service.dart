import 'package:geolocator/geolocator.dart';

/// The result of asking for the phone's position, as plain cases the screen
/// can show a message for — no exceptions to catch.
sealed class LocationResult {
  const LocationResult();
}

final class LocationFound extends LocationResult {
  const LocationFound(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

/// GPS / Location is switched off in quick settings.
final class LocationServiceOff extends LocationResult {
  const LocationServiceOff();
}

final class LocationDenied extends LocationResult {
  const LocationDenied({required this.permanently});

  /// "Don't ask again": only Settings can turn it back on.
  final bool permanently;
}

final class LocationUnavailable extends LocationResult {
  const LocationUnavailable();
}

/// The location permissions are missing from AndroidManifest.xml, so Android
/// can't even ask the user. Only a developer can fix this (README §1c).
final class LocationNotConfigured extends LocationResult {
  const LocationNotConfigured();
}

abstract interface class LocationService {
  Future<LocationResult> current();
  Future<void> openLocationSettings();
  Future<void> openAppSettings();
  double distanceBetween(double lat1, double lng1, double lat2, double lng2);
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<LocationResult> current() async {
    try {
      return await _current();
    } on PermissionDefinitionsNotFoundException {
      return const LocationNotConfigured();
    } on Exception {
      // Never leave the screen stuck on "Finding your location…".
      return const LocationUnavailable();
    }
  }

  Future<LocationResult> _current() async {
    if (!await Geolocator.isLocationServiceEnabled()) return const LocationServiceOff();

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) return const LocationDenied(permanently: false);
    if (permission == LocationPermission.deniedForever) {
      return const LocationDenied(permanently: true);
    }

    try {
      // GPS works without internet, but can be slow indoors: give up after
      // 10 seconds and fall back to the last known position.
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LocationFound(p.latitude, p.longitude);
    } on Exception {
      final last = await Geolocator.getLastKnownPosition();
      return last == null ? const LocationUnavailable() : LocationFound(last.latitude, last.longitude);
    }
  }

  @override
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  @override
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  double distanceBetween(double lat1, double lng1, double lat2, double lng2) =>
      Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
}