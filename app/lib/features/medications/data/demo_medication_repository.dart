import '../../dashboard/data/demo_dashboard_repository.dart';
import '../domain/medication.dart';
import 'medication_repository.dart';

/// Adds the medication to the in-memory demo dashboard (no database, no API).
class DemoMedicationRepository implements MedicationRepository {
  DemoMedicationRepository(this._dashboard);

  final DemoDashboardRepository _dashboard;

  @override
  Future<void> add(NewMedication medication) async {
    await Future<void>.delayed(const Duration(milliseconds: 600)); // show the spinner
    _dashboard.addMedication(medication);
  }
}
