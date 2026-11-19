import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_pusher.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../domain/medication.dart';
import 'medication_local_source.dart';
import 'medication_remote_source.dart';

/// Every write is saved on the phone first (works offline), then uploaded in
/// the background.
abstract interface class MedicationRepository {
  Future<void> add(NewMedication medication);

  /// Every saved medication, A to Z, including ones not scheduled today.
  Future<List<Medication>> all();

  /// Replaces the details of the medication with this [id].
  Future<void> update(String id, NewMedication changes);

  /// Removes the medication and its reminders from this phone and, after the
  /// next sync, from the server and the user's other devices.
  Future<void> delete(String id);

  /// Fires when saved medications may have changed (an edit here, or a sync).
  Stream<void> get changes;
}

class OfflineFirstMedicationRepository implements MedicationRepository {
  OfflineFirstMedicationRepository({
    required MedicationLocalSource local,
    required DashboardRepository dashboard,
    DateTime Function()? clock,
  })  : _local = local,
        _dashboard = dashboard,
        _clock = clock ?? DateTime.now;

  final MedicationLocalSource _local;
  final DashboardRepository _dashboard;
  final DateTime Function() _clock;

  @override
  Future<void> add(NewMedication medication) async {
    await _local.insert(medication, _clock());
    await _dashboard.onLocalDataChanged(); // refresh the list + start uploading
  }

  @override
  Future<List<Medication>> all() => _local.all();

  @override
  Future<void> update(String id, NewMedication changes) async {
    await _local.update(id, changes, _clock());
    await _dashboard.onLocalDataChanged(); // also reschedules the reminders
  }

  @override
  Future<void> delete(String id) async {
    await _local.softDelete(id, _clock());
    await _dashboard.onLocalDataChanged();
  }

  @override
  Stream<void> get changes => _dashboard.changes;
}

/// Plugged into the dashboard's sync: uploads new, edited and deleted
/// medications, then photos.
class MedicationSyncPusher implements SyncPusher {
  MedicationSyncPusher({required MedicationLocalSource local, required MedicationRemoteSource remote})
      : _local = local,
        _remote = remote;

  final MedicationLocalSource _local;
  final MedicationRemoteSource _remote;

  @override
  Future<void> pushPending() async {
    final pending = await _local.pendingForUpload();
    if (pending.isNotEmpty) {
      await _remote.pushMedications(pending);
      await _local.markUploaded(pending);
    }

    for (final photo in await _local.photosToUpload()) {
      try {
        final url = await _remote.uploadPhoto(photo.id, photo.path);
        await _local.setRemotePhoto(photo.id, url);
      } on DioException catch (e) {
        if (e.isOffline) rethrow; // stop; everything retries next sync
        // The server refused this one photo (too big, wrong type). Skip it so
        // it does not block the rest of the sync; the local copy still shows.
        developer.log('Photo upload refused for ${photo.id}: ${e.response?.statusCode}',
            name: 'MedicationSyncPusher');
      }
    }
  }
}
