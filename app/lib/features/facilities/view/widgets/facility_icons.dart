import 'package:flutter/material.dart';

import '../../domain/facility.dart';

/// One icon per kind of place, from the same rounded icon set as the rest of the app.
IconData facilityIcon(FacilityType type) => switch (type) {
      FacilityType.pharmacy => Icons.local_pharmacy_rounded,
      FacilityType.clinic => Icons.medical_services_rounded,
      FacilityType.hospital => Icons.local_hospital_rounded,
    };
