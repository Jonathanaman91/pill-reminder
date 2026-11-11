import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/theme/app_tokens.dart';

/// Loading placeholder that copies the real layout block-for-block, so the
/// page does not jump when the data arrives.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading today’s schedule',
      child: Shimmer.fromColors(
        baseColor: AppColors.surfaceMuted,
        highlightColor: AppColors.surface,
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              AppSpace.screen, AppSpace.xl, AppSpace.screen, AppSpace.xl),
          children: [
            const _Bone(width: 140, height: 14),
            const SizedBox(height: AppSpace.sm),
            const _Bone(width: 240, height: 30),
            const SizedBox(height: AppSpace.lg),
            const _Bone(height: 6),
            const SizedBox(height: AppSpace.md),
            const _Bone(width: 120, height: 16),
            const SizedBox(height: AppSpace.xl),
            const _Bone(height: 196, radius: AppRadius.card),
            const SizedBox(height: AppSpace.section),
            const _Bone(width: 72, height: 13),
            const SizedBox(height: AppSpace.md),
            for (var i = 0; i < 4; i++) ...[
              const _RowBone(),
              const SizedBox(height: AppSpace.lg),
            ],
          ],
        ),
      ),
    );
  }
}

class _RowBone extends StatelessWidget {
  const _RowBone();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _Bone(width: 44, height: 18),
        SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Bone(width: 130, height: 16),
              SizedBox(height: 6),
              _Bone(width: 190, height: 13),
            ],
          ),
        ),
        _Bone(width: 24, height: 24, radius: AppRadius.full),
        SizedBox(width: AppSpace.md),
      ],
    );
  }
}

class _Bone extends StatelessWidget {
  const _Bone({this.width, required this.height, this.radius = AppRadius.bone});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: width ?? double.infinity,
        height: height,
        decoration: BoxDecoration(
          // Shimmer paints over any opaque colour; the hue here does not matter.
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(radius)),
        ),
      ),
    );
  }
}
