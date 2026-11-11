import 'dart:developer' as developer;

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/sync/sync_pusher.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../domain/medication.dart';
import 'medication_local_source.dart';
import 'medication_remote_source.dart';

abstract interface class MedicationRepository {
  /// Saves on the phone first (works offline), then uploads in the background.
  Future<void> add(NewMedication medication);
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
}

/// Plugged into the dashboard's sync: uploads new medications, then photos.
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
