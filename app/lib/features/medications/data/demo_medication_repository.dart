import '../../dashboard/data/demo_dashboard_repository.dart';
import '../domain/medication.dart';
import 'medication_repository.dart';

/// Keeps medications in the in-memory demo dashboard (no database, no API).
class DemoMedicationRepository implements MedicationRepository {
  DemoMedicationRepository(this._dashboard);

  final DemoDashboardRepository _dashboard;

  // Long enough to see each button's spinner.
  static Future<void> _pause() => Future<void>.delayed(const Duration(milliseconds: 600));

  @override
  Future<void> add(NewMedication medication) async {
    await _pause();
    _dashboard.addMedication(medication);
  }

  @override
  Future<List<Medication>> all() async => _dashboard.medications;

  @override
  Future<void> update(String id, NewMedication changes) async {
    await _pause();
    _dashboard.updateMedication(id, changes);
  }

  @override
  Future<void> delete(String id) async {
    await _pause();
    _dashboard.deleteMedication(id);
  }

  @override
  Stream<void> get changes => _dashboard.changes;
}
