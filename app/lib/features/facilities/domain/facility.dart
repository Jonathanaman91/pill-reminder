import 'package:equatable/equatable.dart';

enum FacilityType { pharmacy, clinic, hospital }

/// Government (Ministry of Health) or private. In Malaysia this decides
/// where a prescription is collected, so the app shows it everywhere.
enum Ownership { public, private }

class Facility extends Equatable {
  const Facility({
    required this.id,
    required this.name,
    required this.type,
    required this.ownership,
    required this.is24Hours,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.source,
    this.address,
    this.phone,
    this.openingHours,
  });

  factory Facility.fromJson(Map<String, dynamic> json) => Facility(
        id: json['id'] as String,
        name: json['name'] as String,
        type: FacilityType.values.byName(json['type'] as String),
        ownership: json['ownership'] == 'public' ? Ownership.public : Ownership.private,
        is24Hours: json['is24Hours'] as bool? ?? false,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0,
        source: json['source'] as String? ?? 'osm',
        address: json['address'] as String?,
        phone: json['phone'] as String?,
        openingHours: json['openingHours'] as String?,
      );

  final String id;
  final String name;
  final FacilityType type;
  final Ownership ownership;
  final bool is24Hours;
  final double latitude;
  final double longitude;
  final double distanceMeters;

  /// 'admin' (added in the admin panel) or 'osm' (OpenStreetMap).
  final String source;
  final String? address;
  final String? phone;
  final String? openingHours;

  bool get isPublic => ownership == Ownership.public;

  /// "Government clinic", "Private hospital", "Pharmacy"…
  String get kindLabel => switch (type) {
        FacilityType.pharmacy => isPublic ? 'Government pharmacy' : 'Pharmacy',
        FacilityType.clinic => isPublic ? 'Government clinic' : 'Private clinic',
        FacilityType.hospital => isPublic ? 'Government hospital' : 'Private hospital',
      };

  /// How prescriptions usually work at this kind of place in Malaysia.
  String get prescriptionNote => switch (type) {
        FacilityType.pharmacy =>
          'Pharmacists can fill a written prescription from any doctor and sell '
              'over-the-counter medicine.',
        _ when isPublic =>
          'Government clinics and hospitals give out medicine from their own pharmacy '
              'counter, usually for prescriptions from their own doctors. Bring your '
              'appointment card or prescription slip.',
        _ =>
          'Private clinics usually give you the medicine straight after your '
              'consultation. You can also ask for a written prescription to use at a pharmacy.',
      };

  /// "350 m" or "2.4 km"
  String get distanceLabel => distanceMeters < 1000
      ? '${(distanceMeters / 10).round() * 10} m'
      : '${(distanceMeters / 1000).toStringAsFixed(distanceMeters < 10000 ? 1 : 0)} km';

  Facility withDistance(double meters) => Facility(
        id: id,
        name: name,
        type: type,
        ownership: ownership,
        is24Hours: is24Hours,
        latitude: latitude,
        longitude: longitude,
        distanceMeters: meters,
        source: source,
        address: address,
        phone: phone,
        openingHours: openingHours,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'ownership': ownership.name,
        'is24Hours': is24Hours,
        'latitude': latitude,
        'longitude': longitude,
        'distanceMeters': distanceMeters,
        'source': source,
        'address': address,
        'phone': phone,
        'openingHours': openingHours,
      };

  @override
  List<Object?> get props => [id, distanceMeters];
}

/// The chips above the list. Built around where a prescription comes from.
enum FacilityFilter {
  all('All'),
  pharmacy('Pharmacies'),
  governmentClinic('Gov. clinics'),
  privateClinic('Private clinics'),
  hospital('Hospitals');

  const FacilityFilter(this.label);
  final String label;

  bool matches(Facility f) => switch (this) {
        FacilityFilter.all => true,
        FacilityFilter.pharmacy => f.type == FacilityType.pharmacy,
        FacilityFilter.governmentClinic => f.type == FacilityType.clinic && f.isPublic,
        FacilityFilter.privateClinic => f.type == FacilityType.clinic && !f.isPublic,
        FacilityFilter.hospital => f.type == FacilityType.hospital,
      };
}
