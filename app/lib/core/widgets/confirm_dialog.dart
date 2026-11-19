import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// How the "yes" button of a confirmation looks.
enum ConfirmStyle {
  /// The main action (accent colour), e.g. "Mark as taken".
  primary,

  /// An ordinary choice (neutral grey), e.g. "Skip dose".
  neutral,

  /// Something that cannot be undone (red text), e.g. "Delete".
  destructive,
}

/// The second step before an action that is easy to trigger by accident or
/// hard to take back: the first tap asks, this dialog confirms.
///
/// Returns true only when the confirm button is pressed. Tapping outside,
/// pressing Back or choosing [cancelLabel] all return false, so a slip of the
/// finger can never confirm.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  ConfirmStyle style = ConfirmStyle.primary,
}) async {
  const padding = AppSpace.xl;
  final text = Theme.of(context).textTheme;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialog) {
      void close(bool result) => Navigator.pop(dialog, result);
      return AlertDialog(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // Buttons (radius 8) sit 24 px inside the dialog → outer radius 8 + 24.
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.control + padding)),
        ),
        titlePadding: const EdgeInsets.fromLTRB(padding, padding, padding, 0),
        contentPadding: const EdgeInsets.fromLTRB(padding, AppSpace.md, padding, 0),
        actionsPadding: const EdgeInsets.all(padding),
        title: Text(title, style: text.titleLarge),
        content: Text(message, style: text.bodyLarge?.tabular),
        actions: [
          TextButton(onPressed: () => close(false), child: Text(cancelLabel)),
          switch (style) {
            ConfirmStyle.primary =>
              FilledButton(onPressed: () => close(true), child: Text(confirmLabel)),
            ConfirmStyle.neutral =>
              FilledButton.tonal(onPressed: () => close(true), child: Text(confirmLabel)),
            ConfirmStyle.destructive => TextButton(
                onPressed: () => close(true),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: Text(confirmLabel),
              ),
          },
        ],
      );
    },
  );
  return confirmed ?? false;
}
