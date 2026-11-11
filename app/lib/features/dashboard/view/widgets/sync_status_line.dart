import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../bloc/dashboard_bloc.dart';
import '../../domain/dashboard_snapshot.dart';

/// A quiet one-line status under the headline. Only shown when it matters:
/// while syncing, when offline, or when the last sync failed.
class SyncStatusLine extends StatelessWidget {
  const SyncStatusLine({
    super.key,
    required this.sync,
    required this.snapshot,
    required this.onRetry,
  });

  final SyncIndicator sync;
  final DashboardSnapshot snapshot;
  final VoidCallback onRetry;

  String _savedAt() {
    final at = snapshot.lastSyncedAt;
    if (at == null) return 'not synced yet';
    final sameDay =
        at.year == snapshot.now.year && at.month == snapshot.now.month && at.day == snapshot.now.day;
    return 'saved ${sameDay ? DateFormat.Hm().format(at) : DateFormat('d MMM').format(at)}';
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.tabular;
    final pending = snapshot.pendingSyncCount;
    final changes = pending == 1 ? '1 change' : '$pending changes';

    final (Widget? leading, String? label, bool tappable) = switch (sync) {
      SyncIndicator.idle => (null, null, false),
      SyncIndicator.syncing => (
          const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          'Syncing',
          false,
        ),
      SyncIndicator.offline => (
          const Icon(Icons.cloud_off_rounded, size: 16, color: AppColors.inkSecondary),
          pending > 0 ? 'Offline · $changes will sync later' : 'Offline · schedule ${_savedAt()}',
          true,
        ),
      SyncIndicator.error => (
          const Icon(Icons.sync_problem_rounded, size: 16, color: AppColors.inkSecondary),
          'Couldn’t sync · tap to retry',
          true,
        ),
    };

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topLeft,
      child: label == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: InkWell(
                onTap: tappable ? onRetry : null,
                borderRadius: const BorderRadius.all(Radius.circular(AppRadius.control)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                  child: Row(
                    children: [
                      leading!,
                      const SizedBox(width: AppSpace.sm),
                      Flexible(child: Text(label, style: style)),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
