import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

enum Gender {
  female('Female'),
  male('Male'),
  unspecified('Prefer not to say');

  const Gender(this.label);
  final String label;
}

/// A little about the user's health, so the app is more than a list of
/// alarms: it can show the right context to a doctor, and the admin panel
/// can count (never list) which groups of people use the app.
class HealthProfile extends Equatable {
  const HealthProfile({
    this.dateOfBirth,
    this.gender,
    this.conditions = const [],
    this.allergies,
  });

  factory HealthProfile.fromJson(Map<String, dynamic> json) {
    final dob = json['dateOfBirth'] as String?;
    final gender = json['gender'] as String?;
    return HealthProfile(
      dateOfBirth: dob == null ? null : DateTime.tryParse(dob.substring(0, 10)),
      gender: Gender.values.where((g) => g.name == gender).firstOrNull,
      conditions: [for (final c in json['conditions'] as List<dynamic>? ?? const []) c as String],
      allergies: json['allergies'] as String?,
    );
  }

  static const empty = HealthProfile();

  /// Common long-term conditions in Malaysia, offered as quick choices.
  static const commonConditions = [
    'Diabetes',
    'High blood pressure',
    'High cholesterol',
    'Heart disease',
    'Asthma',
    'Kidney disease',
    'Thyroid problem',
    'Arthritis',
    'Depression or anxiety',
    'Epilepsy',
  ];

  final DateTime? dateOfBirth;
  final Gender? gender;
  final List<String> conditions;
  final String? allergies;

  bool get isEmpty =>
      dateOfBirth == null && gender == null && conditions.isEmpty && (allergies ?? '').isEmpty;

  int? ageOn(DateTime today) {
    final dob = dateOfBirth;
    if (dob == null) return null;
    var age = today.year - dob.year;
    if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) age--;
    return age;
  }

  /// "Age 67 · Diabetes, High blood pressure" for the account sheet.
  String summary(DateTime today) {
    final age = ageOn(today);
    final parts = [
      if (age != null) 'Age $age',
      if (conditions.isNotEmpty) conditions.join(', '),
    ];
    return parts.isEmpty ? 'Add your age, conditions and allergies' : parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
        'dateOfBirth': dateOfBirth == null ? null : DateFormat('yyyy-MM-dd').format(dateOfBirth!),
        'gender': gender?.name,
        'conditions': conditions,
        'allergies': (allergies ?? '').trim().isEmpty ? null : allergies!.trim(),
      };

  HealthProfile copyWith({
    DateTime? Function()? dateOfBirth,
    Gender? Function()? gender,
    List<String>? conditions,
    String? Function()? allergies,
  }) =>
      HealthProfile(
        dateOfBirth: dateOfBirth != null ? dateOfBirth() : this.dateOfBirth,
        gender: gender != null ? gender() : this.gender,
        conditions: conditions ?? this.conditions,
        allergies: allergies != null ? allergies() : this.allergies,
      );

  @override
  List<Object?> get props => [dateOfBirth, gender, conditions, allergies];
}
