import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The screen's primary button. Shows a spinner while the request runs.
class SubmitButton extends StatelessWidget {
  const SubmitButton({
    super.key,
    required this.label,
    required this.submitting,
    required this.onPressed,
  });

  final String label;
  final bool submitting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: submitting ? null : onPressed,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: submitting
            ? const SizedBox.square(
                key: ValueKey('busy'),
                dimension: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.inkSecondary),
              )
            : Text(label, key: const ValueKey('label')),
      ),
    );
  }
}
