import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/medication_photo.dart';
import '../../../core/widgets/message_view.dart';
import '../bloc/medications_cubit.dart';
import '../data/medication_repository.dart';
import '../domain/medication.dart';
import 'add_medication_screen.dart';

/// The Medications tab: every saved medication, including ones that are not
/// scheduled today, each with Edit and Delete.
class MedicationsScreen extends StatelessWidget {
  const MedicationsScreen({super.key, required this.onAddMedication});

  final VoidCallback onAddMedication;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => MedicationsCubit(context.read<MedicationRepository>()),
      child: _MedicationsView(onAddMedication: onAddMedication),
    );
  }
}

class _MedicationsView extends StatelessWidget {
  const _MedicationsView({required this.onAddMedication});

  final VoidCallback onAddMedication;

  void _edit(BuildContext context, Medication medication) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AddMedicationScreen(medication: medication),
    ));
  }

  /// Second step before a delete, because it cannot be undone.
  Future<void> _confirmDelete(BuildContext context, Medication medication) async {
    final cubit = context.read<MedicationsCubit>();
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete ${medication.name}?',
      message: 'Its reminders stop and it leaves your schedule on every device. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Keep it',
      style: ConfirmStyle.destructive,
    );
    if (confirmed) await cubit.delete(medication);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: BlocConsumer<MedicationsCubit, MedicationsState>(
          listenWhen: (prev, curr) => curr.feedback != null && prev.feedback != curr.feedback,
          listener: (context, state) => ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.feedback!.message))),
          builder: (context, state) {
            final medications = state.medications;

            if (state.status == MedicationsStatus.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.status == MedicationsStatus.failure) {
              return MessageView(
                icon: Icons.error_outline_rounded,
                title: 'Couldn’t open your medications',
                body: 'They are still saved on this phone. Please try again.',
                actionLabel: 'Try again',
                actionIcon: Icons.refresh_rounded,
                onAction: context.read<MedicationsCubit>().retry,
              );
            }
            if (medications.isEmpty) {
              return MessageView.empty(onAddMedication: onAddMedication);
            }

            return ListView(
              padding: EdgeInsets.fromLTRB(AppSpace.screen, AppSpace.lg, AppSpace.screen,
                  AppSpace.section + MediaQuery.paddingOf(context).bottom),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        medications.length == 1
                            ? '1 medication'
                            : '${medications.length} medications',
                        style: text.labelMedium?.tabular,
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: onAddMedication,
                      tooltip: 'Add medication',
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.xs),
                Text('Medications', style: text.headlineMedium),
                const SizedBox(height: AppSpace.lg),
                for (final medication in medications)
                  _MedicationRow(
                    key: ValueKey(medication.id),
                    medication: medication,
                    deleting: state.deletingIds.contains(medication.id),
                    onEdit: () => _edit(context, medication),
                    onDelete: () => _confirmDelete(context, medication),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One medication. No card and no border: rows are separated by whitespace,
/// like the dose rows on the Today tab.
class _MedicationRow extends StatelessWidget {
  const _MedicationRow({
    super.key,
    required this.medication,
    required this.deleting,
    required this.onEdit,
    required this.onDelete,
  });

  final Medication medication;
  final bool deleting;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const _photoSize = 48.0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final photo = medication.photo;

    return InkWell(
      onTap: deleting ? null : onEdit,
      borderRadius: const BorderRadius.all(Radius.circular(AppRadius.control)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
        child: Row(
          children: [
            if (photo != null)
              MedicationPhoto(source: photo, radius: AppRadius.control, size: _photoSize)
            else
              Container(
                width: _photoSize,
                height: _photoSize,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
                ),
                child: const Icon(Icons.medication_rounded, color: AppColors.inkTertiary),
              ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: deleting ? 0.5 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(medication.name, style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      medication.detailLabel,
                      style: text.bodyMedium?.tabular,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      medication.scheduleLabel,
                      style: text.bodyMedium?.tabular,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            if (deleting)
              const SizedBox.square(
                dimension: 48,
                child: Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              PopupMenuButton<_RowAction>(
                tooltip: 'Edit or delete ${medication.name}',
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.inkSecondary),
                color: AppColors.surface,
                surfaceTintColor: Colors.transparent,
                onSelected: (action) => switch (action) {
                  _RowAction.edit => onEdit(),
                  _RowAction.delete => onDelete(),
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: _RowAction.edit, child: Text('Edit')),
                  PopupMenuItem(
                    value: _RowAction.delete,
                    child: Text('Delete', style: TextStyle(color: AppColors.danger)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

enum _RowAction { edit, delete }
