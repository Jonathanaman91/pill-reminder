import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/medication_photo.dart';

/// Big tap target at the top of the form. Empty: an invitation to add a
/// photo. Filled: the photo with a "Change" button in its corner.
class PhotoSlot extends StatelessWidget {
  const PhotoSlot({super.key, required this.path, required this.onTap});

  final String? path;
  final VoidCallback? onTap;

  static const _radius = AppRadius.card; // 24
  static const _inset = AppSpace.md; // 12
  /// Button sits 12 px inside a 24 px corner → its radius is 24 − 12 = 12.
  static const _buttonRadius = _radius - _inset;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final photo = path;

    if (photo == null) {
      return Material(
        color: AppColors.surfaceMuted,
        borderRadius: const BorderRadius.all(Radius.circular(_radius)),
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(_radius)),
          child: SizedBox(
            height: 148,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_a_photo_rounded, size: 28, color: AppColors.inkSecondary),
                const SizedBox(height: AppSpace.sm),
                Text('Add a photo of the bottle', style: text.titleSmall),
                const SizedBox(height: 2),
                Text('Optional · helps you recognise it later', style: text.labelMedium),
              ],
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'Medication photo',
      child: Stack(
        children: [
          MedicationPhoto(source: photo, radius: _radius, height: 200),
          Positioned(
            right: _inset,
            bottom: _inset,
            child: FilledButton.icon(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.ink,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(_buttonRadius)),
                ),
              ),
              icon: const Icon(Icons.photo_camera_rounded, size: 18),
              label: const Text('Change'),
            ),
          ),
        ],
      ),
    );
  }
}
