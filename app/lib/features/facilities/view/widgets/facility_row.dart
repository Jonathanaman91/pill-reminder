import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../domain/facility.dart';
import 'facility_icons.dart';

/// One place in the list: what it is, how far, and a quick directions button.
class FacilityRow extends StatelessWidget {
  const FacilityRow({
    super.key,
    required this.facility,
    required this.onTap,
    required this.onDirections,
  });

  final Facility facility;
  final VoidCallback onTap;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final f = facility;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.screen, AppSpace.md, AppSpace.sm, AppSpace.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: AppColors.surfaceMuted, shape: BoxShape.circle),
              child: Icon(facilityIcon(f.type), size: 20, color: AppColors.ink),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.name, style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [f.kindLabel, f.distanceLabel, if (f.is24Hours) 'Open 24 hours'].join(' · '),
                    style: text.bodyMedium?.tabular,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDirections,
              tooltip: 'Directions to ${f.name}',
              icon: const Icon(Icons.directions_rounded, color: AppColors.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
