import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/facility.dart';

/// Details for one place: opening hours, address, phone, how prescriptions
/// work there, and the Directions button.
class FacilitySheet extends StatelessWidget {
  const FacilitySheet({
    super.key,
    required this.facility,
    required this.onDirections,
    required this.onCall,
  });

  final Facility facility;
  final VoidCallback onDirections;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final f = facility;

    final hours = f.is24Hours
        ? 'Open 24 hours'
        : (f.openingHours?.trim().isNotEmpty ?? false)
            ? f.openingHours!
            : 'Opening hours not listed';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.screen, 0, AppSpace.screen, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(f.name, style: text.titleLarge),
            const SizedBox(height: AppSpace.xs),
            Text('${f.kindLabel} · ${f.distanceLabel} away', style: text.bodyMedium?.tabular),
            const SizedBox(height: AppSpace.lg),
            _InfoLine(icon: Icons.schedule_rounded, text: hours),
            if (f.address != null) _InfoLine(icon: Icons.place_rounded, text: f.address!),
            if (f.phone != null) _InfoLine(icon: Icons.call_rounded, text: f.phone!),
            const SizedBox(height: AppSpace.md),
            Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: const BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.inkSecondary),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: Text(f.prescriptionNote, style: text.bodyMedium)),
                ],
              ),
            ),
            if (f.source != 'admin') ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                f.source == 'demo'
                    ? 'Sample place for demo mode.'
                    : 'Details from OpenStreetMap and may be out of date. Call ahead to check.',
                style: text.labelMedium,
              ),
            ],
            const SizedBox(height: AppSpace.xl),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onDirections,
                    icon: const Icon(Icons.directions_rounded),
                    label: const Text('Directions'),
                  ),
                ),
                if (f.phone != null) ...[
                  const SizedBox(width: AppSpace.sm),
                  OutlinedButton.icon(
                    onPressed: onCall,
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('Call'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.inkSecondary),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge?.tabular)),
        ],
      ),
    );
  }
}
