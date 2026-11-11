import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Shows a pill-bottle photo from a file on this phone or from the server.
/// If the image can't load (offline, file deleted) it shows a plain tile
/// with a pill icon instead of a broken-image symbol.
class MedicationPhoto extends StatelessWidget {
  const MedicationPhoto({
    super.key,
    required this.source,
    required this.radius,
    this.size,
    this.height,
  });

  final String source;
  final double radius;
  final double? size; // square
  final double? height; // full width

  @override
  Widget build(BuildContext context) {
    final w = size ?? double.infinity;
    final h = size ?? height;
    Widget fallback(BuildContext _, Object _, StackTrace? _) => Container(
          width: w,
          height: h,
          color: AppColors.surfaceMuted,
          alignment: Alignment.center,
          child: const Icon(Icons.medication_rounded, color: AppColors.inkTertiary),
        );

    final cacheWidth = size == null ? null : (size! * MediaQuery.devicePixelRatioOf(context)).round();
    final image = source.startsWith('http')
        ? Image.network(source, width: w, height: h, fit: BoxFit.cover,
            cacheWidth: cacheWidth, errorBuilder: fallback)
        : Image.file(File(source), width: w, height: h, fit: BoxFit.cover,
            cacheWidth: cacheWidth, errorBuilder: fallback);

    return ClipRRect(
      borderRadius: BorderRadius.all(Radius.circular(radius)),
      child: image,
    );
  }
}
